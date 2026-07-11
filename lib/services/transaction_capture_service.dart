import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_transaction.dart';
import 'hive_service.dart';
import 'merchant_resolution_service.dart';

/// Captures transactions from the native layer (SMS receiver + notification
/// listener).
///
/// Two paths:
///  1. Live: EventChannel stream while the app is open.
///  2. Buffered: events captured while the app was closed are persisted
///     natively and drained here on startup via MethodChannel.
///
/// The same two paths also carry `categorizeAction` events fired by the
/// system categorize notification's buttons (CategorizeActionReceiver /
/// MainActivity on the native side), so a category chosen from the
/// notification is written into Hive through the exact same
/// [HiveService.saveTransaction] call this service uses — without the app
/// ever needing to come to the foreground while its engine is alive, and
/// with the action buffered + drained on next launch if the process was dead.
class TransactionCaptureService {
  final HiveService hiveService;
  final MerchantResolutionService resolutionService;

  static const EventChannel _eventChannel =
      EventChannel('com.example.fintrack/transactions');
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.fintrack/methods');

  /// Fired when the user taps "Other" (or the notification body) on the
  /// categorize notification — carries the Hive key of the transaction so
  /// the UI can open the existing in-app categorize flow (free-text entry).
  static final StreamController<int> _openCategorizeController =
      StreamController<int>.broadcast();
  static Stream<int> get openCategorizeRequests =>
      _openCategorizeController.stream;

  /// Quick-pick labels shown as the first pill row on the notification and
  /// in the in-app categorize bar.
  static const List<String> quickPicks = ['Personal', 'Rent', 'Friend', 'Gift'];

  /// Recent (amount, time) signatures used to drop duplicates — e.g. the same
  /// transaction arriving both as a bank SMS and as a UPI app notification.
  final List<_Signature> _recent = [];

  TransactionCaptureService(this.hiveService, this.resolutionService);

  Future<void> start() async {
    // 1) Drain anything captured while the app was closed — this includes
    //    categorize-notification button presses that happened while the
    //    process was dead.
    try {
      final pending = await _methodChannel
          .invokeMethod<List<dynamic>>('drainPendingTransactions');
      if (pending != null) {
        for (final e in pending) {
          if (e is Map) await _handleEvent(Map<Object?, Object?>.from(e));
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Drain pending error: $e');
    }

    // 2) Listen live.
    _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) async {
        try {
          if (event is Map) await _handleEvent(event);
        } catch (e) {
          // ignore: avoid_print
          print('Transaction capture error: $e');
        }
      },
      onError: (Object e) {
        // ignore: avoid_print
        print('Transaction capture stream error: $e');
      },
    );
  }

  // ---------------------------------------------------------------------
  // Permissions helpers (used by PermissionsScreen)
  // ---------------------------------------------------------------------

  static Future<bool> isNotificationAccessGranted() async {
    try {
      return await _methodChannel
              .invokeMethod<bool>('isNotificationAccessGranted') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openNotificationAccessSettings() async {
    try {
      await _methodChannel.invokeMethod('openNotificationAccessSettings');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------

  Future<void> _handleEvent(Map event) async {
    // Raw capture log — the FIRST thing that happens, before any regex
    // filtering, so real SMS / notification formats can be inspected during
    // testing with:  adb logcat -s flutter | grep capture-raw
    debugPrint(
      '[FinTrack][capture-raw] source=${event['source'] ?? '?'} '
      'sender=${event['sender'] ?? ''} package=${event['package'] ?? ''} '
      'title="${event['title'] ?? ''}" text="${event['text'] ?? ''}"',
    );

    // Categorize-notification button actions arrive over the same live /
    // buffered channels as captures — route them before any parsing.
    if (event['type'] == 'categorizeAction') {
      await _handleCategorizeAction(event);
      return;
    }

    final text = event['text']?.toString() ?? '';
    final title = event['title']?.toString() ?? '';
    final combined = '$title $text'.trim();
    if (combined.isEmpty) return;

    final lower = combined.toLowerCase();

    // Skip OTPs, promos, balance alerts, future/failed payments,
    // and pure credits (income) — we track spending.
    if (lower.contains('otp') || lower.contains('one time password')) return;
    if (lower.contains('will be debited') || lower.contains('autopay')) return;
    if (lower.contains('failed') || lower.contains('declined')) return;
    if (lower.contains('requested money') || lower.contains('payment request')) {
      return;
    }
    final isDebit = lower.contains('debited') ||
        lower.contains('paid') ||
        lower.contains('sent') ||
        lower.contains('spent') ||
        lower.contains('withdrawn') ||
        lower.contains('purchase');
    final isCredit =
        lower.contains('credited') || lower.contains('received');
    if (!isDebit && isCredit) return; // income, not an expense
    if (!isDebit) return;

    var amount = _extractAmount(combined);
    if (amount <= 0) {
      // The text passed the debit-keyword gate but no amount could be
      // confidently extracted. Don't silently drop the event — record a
      // ₹0 placeholder so it at least surfaces for manual entry.
      debugPrint(
        '[FinTrack][capture-warn] Debit keyword present but no amount '
        'extracted — saving ₹0 placeholder for manual entry. Raw: "$combined"',
      );
      amount = 0.0;
    }

    // De-duplicate: same amount seen in the last 3 minutes.
    // (Skipped for ₹0 placeholders — distinct fallback captures would
    // otherwise collide on the shared 0 signature.)
    final now = DateTime.now();
    _recent.removeWhere((s) => now.difference(s.time).inMinutes >= 3);
    if (amount > 0) {
      if (_recent.any((s) => (s.amount - amount).abs() < 0.01)) return;
      _recent.add(_Signature(amount, now));
    }

    // Timestamp: buffered events carry the original capture time.
    var date = now;
    final capturedAt = event['capturedAt'];
    if (capturedAt is int) {
      date = DateTime.fromMillisecondsSinceEpoch(capturedAt);
    }

    final merchant = _extractMerchant(combined, event);
    final isP2P = _isP2P(lower);

    final tx = AppTransaction()
      ..amount = amount
      ..merchant = merchant
      ..date = date
      ..isUncategorized = true;

    // ₹0 placeholders always need manual attention — never auto-categorize.
    if (!isP2P && amount > 0) {
      try {
        final rule = await resolutionService.resolveMerchant(merchant);
        if (rule != null) {
          tx.customCategory = rule.category;
          tx.isUncategorized = false;
        } else {
          // Fallback: partial/contains match across all saved rules
          final name = merchant.toLowerCase().trim();
          for (final r in hiveService.merchantRuleBox.values) {
            if (name.contains(r.merchantName) || r.merchantName.contains(name)) {
              tx.customCategory = r.category;
              tx.isUncategorized = false;
              break;
            }
          }
        }
      } catch (_) {
        // Resolution is best-effort; the categorize flows handle the rest.
      }
    }

    await hiveService.saveTransaction(tx);

    try {
      if (tx.isUncategorized) {
        // Rich system heads-up notification with category pills — posted
        // immediately so the banner appears as the transaction is captured.
        await postCategorizeNotification(
          hiveService,
          tx,
          sourceLabel: _sourceLabel(event, lower),
        );
      } else {
        // Auto-categorized: a simple confirmation is enough.
        await _methodChannel.invokeMethod('showNotification', {
          'title': '✅ ₹${amount.toStringAsFixed(0)} → ${tx.customCategory}',
          'body':
              '₹${amount.toStringAsFixed(0)} spent at $merchant auto-categorized as ${tx.customCategory}.',
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('Show notification MethodChannel error: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Categorize-notification actions
  // ---------------------------------------------------------------------

  Future<void> _handleCategorizeAction(Map event) async {
    final action = event['action']?.toString();
    final txKey = int.tryParse(event['txKey']?.toString() ?? '');
    if (action == null || txKey == null) return;

    final tx = hiveService.transactionBox.get(txKey);
    if (tx == null) {
      debugPrint(
        '[FinTrack][categorize-warn] Action "$action" for unknown tx key $txKey',
      );
      return;
    }

    switch (action) {
      case 'setCategory':
        final category = event['category']?.toString() ?? '';
        if (category.isEmpty) return;
        tx
          ..customCategory = category
          ..isUncategorized = false
          ..isSkipped = false;
        // Same save path as capture — updates Hive, the stream, Firestore.
        await hiveService.saveTransaction(tx);
        break;

      case 'skip':
        tx.isSkipped = true;
        await hiveService.saveTransaction(tx);
        break;

      case 'open':
        // "Other" — hand off to the in-app categorize flow (free text).
        _openCategorizeController.add(txKey);
        break;
    }
  }

  /// Posts the rich categorize notification for [tx]. Also used by the
  /// dashboard's "simulate transaction" button so the test path matches the
  /// real capture path.
  static Future<void> postCategorizeNotification(
    HiveService hiveService,
    AppTransaction tx, {
    String sourceLabel = 'App',
  }) async {
    final key = tx.key;
    if (key is! int) return; // must be saved to Hive first

    // Second pill row: the user's selected categories (fall back to all,
    // then to sensible defaults). Hard cap of 4 — the RemoteViews row has
    // exactly 4 fixed-width slots and cannot wrap.
    var cats = hiveService.categoryBox.values
        .where((c) => c.isSelected)
        .map((c) => c.name)
        .toList();
    if (cats.isEmpty) {
      cats = hiveService.categoryBox.values.map((c) => c.name).toList();
    }
    cats = cats
        .where((n) => n != 'Other' && !quickPicks.contains(n))
        .take(4)
        .toList();
    if (cats.isEmpty) cats = ['Food', 'Shopping', 'Travel', 'Bills'];

    await _methodChannel.invokeMethod('showCategorizeNotification', {
      'txKey': key,
      'amount': tx.amount,
      'payee': tx.merchant,
      'sourceLabel': sourceLabel,
      'timeLabel': _formatTime(tx.date),
      'quickPicks': quickPicks.take(4).toList(),
      'categories': cats,
    });
  }

  /// Cancels a still-showing categorize notification for [txKey] — used when
  /// the user categorizes the transaction in-app instead.
  static Future<void> cancelCategorizeNotification(int txKey) async {
    try {
      await _methodChannel
          .invokeMethod('cancelCategorizeNotification', {'txKey': txKey});
    } catch (_) {}
  }

  static String _formatTime(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $ampm';
  }

  String _sourceLabel(Map event, String lower) {
    if (event['source'] == 'sms') {
      return lower.contains('upi') ? 'UPI' : 'SMS';
    }
    final pkg = event['package']?.toString().toLowerCase() ?? '';
    const upiApps = ['phonepe', 'paytm', 'gpay', 'nbu.paisa', 'bhim', 'upi'];
    if (upiApps.any(pkg.contains) || lower.contains('upi')) return 'UPI';
    return 'App';
  }

  // ---------------------------------------------------------------------
  // Amount extraction
  // ---------------------------------------------------------------------

  /// Extraction order (first confident hit wins):
  ///  1. Currency marker + digits, with or without a space:
  ///     "Rs.450", "Rs 1,450.50", "INR2,000", "₹450", "Rs150", "Rs.1450/-"
  ///  2. Debit/credit keyword followed by an amount (currency optional):
  ///     "debited by Rs150", "debited with 150.00", "paid 450"
  ///  3. Amount followed by a debit/credit keyword:
  ///     "150.00 debited", "150 credited", "1,200 has been debited"
  double _extractAmount(String text) {
    // (?<![a-z]) keeps the "rs" inside words like "offers" from matching.
    final withCurrency = RegExp(
      r'(?<![a-z])(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    final keywordThenAmount = RegExp(
      r'(?:debited|credited|paid|sent|spent|withdrawn|purchase(?:\s+of)?)\s*'
      r'(?:by|of|for|with|:)?\s*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    final amountThenKeyword = RegExp(
      r'(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)\s*'
      r'(?:is\s+|was\s+|has\s+been\s+)?'
      r'(?:debited|credited|paid|sent|spent|withdrawn)',
      caseSensitive: false,
    );

    var m = withCurrency.firstMatch(text);
    var v = _parseAmount(m?.group(1));
    if (v > 0) return v;

    m = keywordThenAmount.firstMatch(text);
    v = _parseAmount(m?.group(1));
    if (v > 0) return v;

    // Keyword-adjacent digits are less reliable near account numbers
    // ("A/c XX1234 debited"), so mask those tokens before matching.
    final sanitized = text.replaceAll(
      RegExp(
        r'(?:a/c|acct|account|card)\s*(?:no\.?)?\s*[x\*]*[\d]+[x\*\d]*',
        caseSensitive: false,
      ),
      ' ',
    );
    m = amountThenKeyword.firstMatch(sanitized);
    return _parseAmount(m?.group(1));
  }

  double _parseAmount(String? raw) {
    if (raw == null) return 0.0;
    return double.tryParse(raw.replaceAll(',', '')) ?? 0.0;
  }

  /// Tries common Indian bank/UPI phrasings before falling back to the
  /// notification title or SMS sender.
  String _extractMerchant(String text, Map event) {
    final patterns = <RegExp>[
      // "trf to SWIGGY", "sent to Rahul", "paid to Amazon Pay"
      RegExp(r'(?:trf to|transfer to|sent to|paid to|payment to|to)\s+([A-Za-z0-9@._&\x27 -]{2,40}?)(?=\s+(?:on|via|ref|upi|from|a/c|using|for)\b|[.,;]|$)',
          caseSensitive: false),
      // "spent at DMART", "purchase at Reliance"
      RegExp(r'(?:at|towards)\s+([A-Za-z0-9@._&\x27 -]{2,40}?)(?=\s+(?:on|via|ref|upi|from|using)\b|[.,;]|$)',
          caseSensitive: false),
      // "Info: UPI/1234/SWIGGY"
      RegExp(r'info[:\s]+(?:upi[/-])?(?:[\d]+[/-])?([A-Za-z0-9@._&\x27 -]{2,40})',
          caseSensitive: false),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      final candidate = m?.group(1)?.trim();
      if (candidate != null && candidate.length >= 2) {
        return _cleanMerchant(candidate);
      }
    }

    if (event['source'] == 'notification') {
      final title = event['title']?.toString().trim() ?? '';
      if (title.isNotEmpty) return _cleanMerchant(title);
    }
    final sender = event['sender']?.toString().trim() ?? '';
    return sender.isNotEmpty ? sender : 'Unknown';
  }

  String _cleanMerchant(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Strip trailing UPI handles for readability: "swiggy@icici" -> "swiggy"
    final at = s.indexOf('@');
    if (at > 2) s = s.substring(0, at);
    if (s.length > 40) s = s.substring(0, 40);
    // Title-case all-caps merchants.
    if (s == s.toUpperCase() && s.length > 3) {
      s = s
          .toLowerCase()
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');
    }
    return s;
  }

  bool _isP2P(String lower) {
    return lower.contains('vpa') ||
        (lower.contains('upi') && lower.contains(' to ')) ||
        lower.contains('transfer');
  }
}

class _Signature {
  final double amount;
  final DateTime time;
  _Signature(this.amount, this.time);
}

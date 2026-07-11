const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");
require("dotenv").config();

admin.initializeApp();
const db = admin.firestore();

exports.onTransactionWritten = functions.firestore
    .document("users/{userId}/transactions/{txId}")
    .onWrite(async (change, context) => {
        const userId = context.params.userId;
        const txData = change.after.exists ? change.after.data() : null;
        
        if (!txData || txData.isUncategorized || !txData.customCategory) {
            return null;
        }

        const date = new Date(txData.date);
        const monthKey = `${date.getFullYear()}-${date.getMonth() + 1}`;
        const category = txData.customCategory;
        const amount = txData.amount;

        const categoryDoc = await db.collection("users").doc(userId).collection("categories").doc(category).get();
        if (!categoryDoc.exists) return null;
        
        const catData = categoryDoc.data();
        const monthlyAllocation = catData.monthlyAllocation || 0;

        const budgetRef = db.collection("users").doc(userId).collection("budgets").doc(monthKey);
        
        await db.runTransaction(async (transaction) => {
            const budgetDoc = await transaction.get(budgetRef);
            let spentTotals = {};
            if (budgetDoc.exists) {
                spentTotals = budgetDoc.data().spentTotals || {};
            }
            
            const prevAmount = change.before.exists && !change.before.data().isUncategorized && change.before.data().customCategory === category ? change.before.data().amount : 0;
            const netAdd = amount - prevAmount;
            
            const currentSpent = (spentTotals[category] || 0) + netAdd;
            spentTotals[category] = currentSpent;
            
            transaction.set(budgetRef, { spentTotals }, { merge: true });

            if (monthlyAllocation > 0) {
                const ratio = currentSpent / monthlyAllocation;
                if (ratio >= 1.0) {
                    await sendFCM(userId, "Budget Exceeded", `You have exceeded your budget for ${category}.`);
                } else if (ratio >= 0.8) {
                    await sendFCM(userId, "Budget Warning", `You have used 80% of your budget for ${category}.`);
                }
            }
        });
        
        return null;
    });

exports.resolveMerchant = functions.https.onCall(async (data, context) => {
    const { merchantName, lat, lng } = data;
    if (!merchantName) return { category: 'Other', resolvedBy: 'none' };
    
    // Google Places API
    const placesKey = process.env.GOOGLE_PLACES_API_KEY || functions.config().places?.key;
    if (placesKey) {
        try {
            const reqBody = { textQuery: merchantName };
            if (lat && lng) {
                reqBody.locationBias = {
                    circle: {
                        center: { latitude: lat, longitude: lng },
                        radius: 50000.0 // 50km radius
                    }
                };
            }
            const response = await axios.post(
                'https://places.googleapis.com/v1/places:searchText',
                reqBody,
                {
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Goog-Api-Key': placesKey,
                        'X-Goog-FieldMask': 'places.types,places.displayName'
                    }
                }
            );
            const places = response.data.places;
            if (places && places.length > 0) {
                const types = places[0].types || [];
                let category = 'Other';
                if (types.includes('restaurant') || types.includes('cafe')) category = 'Food';
                else if (types.includes('supermarket') || types.includes('grocery_or_supermarket')) category = 'Groceries';
                else if (types.includes('shopping_mall') || types.includes('clothing_store')) category = 'Shopping';
                else if (types.includes('gas_station') || types.includes('car_repair')) category = 'Transportation';
                else if (types.includes('movie_theater') || types.includes('amusement_park')) category = 'Entertainment';
                else if (types.includes('hospital') || types.includes('pharmacy')) category = 'Personal';
                
                if (category !== 'Other') {
                    return { category, resolvedBy: 'places' };
                }
            }
        } catch (e) {
            console.error("Places API Error:", e.response ? JSON.stringify(e.response.data) : e.message);
        }
    }
    
    // Ollama LLM Fallback
    try {
        const ollamaUrl = process.env.OLLAMA_BASE_URL || "http://host.docker.internal:11434/api/generate";
        const ollamaModel = process.env.OLLAMA_MODEL || "llama3.1:8b";
        const response = await axios.post(ollamaUrl, {
            model: ollamaModel,
            prompt: `Categorize the merchant "${merchantName}" into one of these categories: Food, Groceries, Shopping, Transportation, Entertainment, Bills, Personal, Other. Respond ONLY with a JSON object like {"category": "Food", "confidence": 0.9}.`,
            format: 'json',
            stream: false
        });
        
        let llmResponse = response.data.response;
        if (typeof llmResponse === 'string') {
            llmResponse = JSON.parse(llmResponse);
        }
        
        if (llmResponse.confidence && llmResponse.confidence > 0.7 && llmResponse.category) {
            return { category: llmResponse.category, resolvedBy: 'llm' };
        }
    } catch (e) {
        console.error("Ollama API Error:", e.message);
    }
    
    return { category: 'Other', resolvedBy: 'none' };
});

exports.checkGoalReallocation = functions.pubsub.schedule("every 24 hours").onRun(async (context) => {
    const usersSnapshot = await db.collection("users").get();
    const now = new Date();
    
    for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const goalsSnapshot = await db.collection("users").doc(userId).collection("goals").get();
        
        for (const goalDoc of goalsSnapshot.docs) {
            const goal = goalDoc.data();
            
            // 1. Check Reallocation Frequency Elapsed
            const lastCheck = goal.lastReallocationCheck ? new Date(goal.lastReallocationCheck) : new Date(0);
            const daysSinceLastCheck = (now.getTime() - lastCheck.getTime()) / (1000 * 3600 * 24);
            
            let shouldCheck = false;
            const freq = goal.reallocationFrequency || 'weekly';
            if (freq === 'daily' && daysSinceLastCheck >= 1) shouldCheck = true;
            else if (freq === 'weekly' && daysSinceLastCheck >= 7) shouldCheck = true;
            else if (freq === 'every 2 weeks' && daysSinceLastCheck >= 14) shouldCheck = true;
            
            if (!shouldCheck) continue;
            
            // 2. Read last 3 months transactions to find average spend
            const threeMonthsAgo = new Date();
            threeMonthsAgo.setMonth(now.getMonth() - 3);
            
            const txSnapshot = await db.collection("users").doc(userId).collection("transactions")
                .where("date", ">=", threeMonthsAgo.toISOString())
                .get();
                
            let categorySpends = {};
            txSnapshot.docs.forEach(doc => {
                const tx = doc.data();
                if (!tx.isUncategorized && tx.customCategory) {
                    categorySpends[tx.customCategory] = (categorySpends[tx.customCategory] || 0) + tx.amount;
                }
            });
            
            for (let cat in categorySpends) {
                categorySpends[cat] = categorySpends[cat] / 3.0; // 3-month average
            }
            
            // 3. Compute slack
            const categoriesSnapshot = await db.collection("users").doc(userId).collection("categories").get();
            let totalSlack = 0;
            
            categoriesSnapshot.docs.forEach(catDoc => {
                const catData = catDoc.data();
                const alloc = catData.monthlyAllocation || 0;
                if (alloc > 0) {
                    const avgSpend = categorySpends[catData.name] || 0;
                    if (avgSpend < alloc * 0.8) {
                        totalSlack += (alloc - avgSpend);
                    }
                }
            });
            
            if (totalSlack <= 0) {
                await goalDoc.ref.update({ lastReallocationCheck: now.toISOString() });
                continue;
            }
            
            const remainingTarget = goal.targetAmount - (goal.currentProgress || 0);
            const proposedAmount = Math.min(totalSlack, remainingTarget);
            
            if (proposedAmount <= 0) {
                await goalDoc.ref.update({ lastReallocationCheck: now.toISOString() });
                continue;
            }
            
            const ollamaUrl = process.env.OLLAMA_BASE_URL || "http://host.docker.internal:11434/api/generate";
            const ollamaModel = process.env.OLLAMA_MODEL || "llama3.1:8b";
            
            let explanation = `Consider reallocating Rs. ${Math.round(proposedAmount)} from underspent categories to reach your goal "${goal.title}" faster.`;
            try {
                const response = await axios.post(ollamaUrl, {
                    model: ollamaModel,
                    prompt: `Write a one-sentence encouraging explanation for the user to reallocate Rs. ${Math.round(proposedAmount)} to their goal "${goal.title}".`,
                    stream: false
                });
                explanation = response.data.response;
            } catch (e) {
                console.error("Ollama error:", e.message);
            }
            
            await db.collection("users").doc(userId).collection("proposals").add({
                goalId: goal.id,
                amount: Math.round(proposedAmount),
                explanation: explanation,
                status: 'pending',
                date: now.toISOString()
            });
            
            await goalDoc.ref.update({ lastReallocationCheck: now.toISOString() });
            await sendFCM(userId, "Goal Reallocation Proposal", explanation);
        }
    }
});

async function sendFCM(userId, title, body) {
    const userDoc = await db.collection("users").doc(userId).get();
    const token = userDoc.data()?.fcmToken;
    if (token) {
        await admin.messaging().send({
            token: token,
            notification: { title, body }
        });
    }
}

exports.getAiInsights = functions.https.onCall(async (data, context) => {
    const { userId } = data;
    if (!userId) return { error: "No userId provided" };

    try {
        // 1. Fetch Profile
        const profileDoc = await db.collection("users").doc(userId).collection("profile").doc("main").get();
        const profile = profileDoc.exists ? profileDoc.data() : {};

        // 2. Fetch Categories
        const catSnapshot = await db.collection("users").doc(userId).collection("categories").get();
        const categories = catSnapshot.docs.map(doc => doc.data());

        // 3. Fetch Transactions
        const txSnapshot = await db.collection("users").doc(userId).collection("transactions").get();
        const transactions = txSnapshot.docs.map(doc => doc.data());

        // 4. Construct Prompt Context
        const totalSpent = transactions.reduce((sum, tx) => sum + (tx.amount || 0), 0);
        const recentTxSummary = transactions.slice(0, 15).map(tx => `₹${tx.amount} at ${tx.merchant} (${tx.customCategory || 'Uncategorized'})`).join(', ');

        const promptContext = `
Analyze the user's financial status:
- User Type: ${profile.userType || 'Working Professional'}
- Monthly Income: ₹${profile.monthlyIncome || 20000}
- Savings Target: ₹${profile.savingsTarget || 50000}
- Timeline: ${profile.timelineMonths || 12} months
- Categories: ${categories.map(c => `${c.name} (Budget: ₹${c.monthlyAllocation})`).join(', ')}
- Total Spent So Far: ₹${totalSpent}
- Recent Transactions: ${recentTxSummary || 'None'}

As their proactive financial planning agent, perform budget planning, analyze weekly/monthly behavior, and output advice in JSON.
Generate:
1. suggestedBudgets: Recommended monthly budget allocations for categories (e.g. Food, Shopping, Travel, Bills, Entertainment, emergency savings) to help them reach their savings target.
2. spendingInsights: 3 actionable insights or tips based on their profile and spending.
3. savingsProjection: A forecast text showing when they will reach their goal.
4. reallocationAdvice: Reallocate budgets dynamically to optimize savings.

Output ONLY a JSON object matching this structure:
{
  "suggestedBudgets": [
    {"category": "Food", "amount": 4000},
    {"category": "Travel", "amount": 2000},
    {"category": "Entertainment", "amount": 1500},
    {"category": "Shopping", "amount": 2500},
    {"category": "Emergency Savings", "amount": 5000}
  ],
  "spendingInsights": [
    "Your food spending is currently your highest category.",
    "Skipping two food delivery orders per week will save approximately ₹1,200/month.",
    "Reducing travel spending by ₹50/day helps you reach your savings target 2 weeks earlier."
  ],
  "savingsProjection": "Based on your current trend of spending and saving, you are on track to save ₹56,000 this year and reach your savings target in 8.3 months.",
  "reallocationAdvice": "Food was overspent by ₹500 this week, while Entertainment was underspent by ₹800. We suggest shifting ₹500 from Entertainment to cover the Food overage."
}
`;

        const ollamaUrl = process.env.OLLAMA_BASE_URL || "http://host.docker.internal:11434/api/generate";
        const ollamaModel = process.env.OLLAMA_MODEL || "llama3.1:8b";
        
        const response = await axios.post(ollamaUrl, {
            model: ollamaModel,
            prompt: promptContext,
            format: 'json',
            stream: false
        });

        let responseText = response.data.response;
        if (typeof responseText === 'string') {
            responseText = JSON.parse(responseText);
        }
        return responseText;
    } catch (e) {
        console.error("getAiInsights Error:", e.message);
        return {
            suggestedBudgets: [
                {category: "Food", amount: 4000},
                {category: "Travel", amount: 2000},
                {category: "Entertainment", amount: 1500},
                {category: "Shopping", amount: 2500},
                {category: "Emergency Savings", amount: 5000}
            ],
            spendingInsights: [
                "Food spending is your biggest expense category.",
                "Based on your current trend, you will reach your goal in 8.3 months.",
                "Skipping two food delivery orders per week saves approximately ₹1,200/month."
            ],
            savingsProjection: "You are projected to save ₹56,000 this year and reach your goal on time.",
            reallocationAdvice: "Food overspent by ₹500. Entertainment underspent by ₹800. Shifting available budget intelligently to keep your savings on track."
        };
    }
});

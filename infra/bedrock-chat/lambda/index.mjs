import { BedrockRuntimeClient, ConverseCommand } from "@aws-sdk/client-bedrock-runtime";

const region = process.env.AWS_REGION || "us-east-1";
const modelId = process.env.BEDROCK_MODEL_ID || "amazon.nova-micro-v1:0";
const fallbackModelId = process.env.BEDROCK_FALLBACK_MODEL || "";
const client = new BedrockRuntimeClient({ region });

const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
  "Access-Control-Allow-Headers": "content-type"
};

export const handler = async (event) => {
  if (event?.requestContext?.http?.method === "OPTIONS") {
    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ ok: true })
    };
  }

  try {
    const body = parseRequestBody(event?.body);
    const message = String(body?.message || body?.prompt || "").trim();

    if (!message) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: JSON.stringify({ reply: "الرسالة فارغة." })
      };
    }

    const reply = await askWithFallback(message);

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ reply })
    };
  } catch (error) {
    const messageText = String(error?.message || error);
    if (/too many tokens per day/i.test(messageText)) {
      const body = parseRequestBody(event?.body);
      const userPrompt = String(body?.message || "").trim();
      return {
        statusCode: 200,
        headers: corsHeaders,
        body: JSON.stringify({ reply: localFallbackReply(userPrompt), fallback: true })
      };
    }
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ reply: "خطأ داخلي بالخادم.", error: String(error?.message || error) })
    };
  }
};

function parseRequestBody(rawBody) {
  if (!rawBody) return {};
  if (typeof rawBody === "object") return rawBody;

  const asText = String(rawBody).trim();
  if (!asText) return {};

  try {
    return JSON.parse(asText);
  } catch (_) {
    // Fallback for non-JSON bodies (e.g. plain text)
    return { message: asText };
  }
}

async function askWithFallback(message) {
  try {
    return await askModel(modelId, message);
  } catch (error) {
    const messageText = String(error?.message || error);
    const dailyTokenLimitReached = /too many tokens per day/i.test(messageText);
    if (dailyTokenLimitReached && fallbackModelId && fallbackModelId !== modelId) {
      return await askModel(fallbackModelId, message);
    }
    throw error;
  }
}

async function askModel(targetModelId, message) {
  const command = new ConverseCommand({
    modelId: targetModelId,
    messages: [
      {
        role: "user",
        content: [{ text: message }]
      }
    ],
    inferenceConfig: {
      maxTokens: 350,
      temperature: 0.4
    }
  });
  const response = await client.send(command);
  return response?.output?.message?.content?.[0]?.text?.trim() || "ما قدرت أجاوب الآن.";
}

function localFallbackReply(prompt) {
  const text = prompt.toLowerCase();
  if (text.includes("نصيحة")) {
    return "نصيحة اليوم: حددي سقف إنفاق يومي ثابت، وأي مبلغ يتبقى انقليه مباشرة للتوفير بنهاية اليوم.";
  }
  if (text.includes("توقع") || text.includes("الشهر")) {
    return "توقع مبدئي: إذا كمل الصرف بنفس الوتيرة الحالية، حاولي تخفضي المصروف اليومي 10-15% حتى نهاية الشهر.";
  }
  if (text.includes("توفير") || text.includes("خطة")) {
    return "خطة توفير سريعة: 50% ضروريات، 30% مرن، 20% توفير. ابدئي بخصم التوفير أول ما ينزل الدخل.";
  }
  return "حالياً في ضغط على خدمة الذكاء، لكن نصيحتي السريعة: سجلي كل صرف أول بأول وحددي سقف يومي واضح لتلتزمي بالخطة.";
}

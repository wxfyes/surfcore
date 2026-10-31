import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import https from 'node:https';

const CONFIG_PATH = path.join(os.homedir(), '.dsh', 'surfcore', 'gemini-vision.json');

function readVisionConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
      return JSON.parse(raw);
    }
  } catch (_) {}
  return {
    apiKey: '',
    model: 'gemini-3.8-flash',
    proxy: 'http://127.0.0.1:27890',
    enabled: true,
  };
}

/**
 * 专属按需代理通道：仅在调用 Google Gemini 时挂载代理，其余请求完全不走代理
 */
function requestViaProxy({ proxyUrl, targetHost, targetPort = 443, path: reqPath, method = 'POST', headers = {}, body = '', timeoutMs = 7000 }) {
  return new Promise((resolve, reject) => {
    let proxyHost = '127.0.0.1';
    let proxyPort = 27890;
    try {
      if (proxyUrl) {
        const u = new URL(proxyUrl);
        proxyHost = u.hostname || '127.0.0.1';
        proxyPort = Number(u.port) || 27890;
      }
    } catch (_) {}

    const connectReq = http.request({
      host: proxyHost,
      port: proxyPort,
      method: 'CONNECT',
      path: `${targetHost}:${targetPort}`,
      timeout: timeoutMs,
    });

    let finished = false;
    const timer = setTimeout(() => {
      if (!finished) {
        finished = true;
        connectReq.destroy();
        reject(new Error(`Proxy CONNECT timeout (${timeoutMs}ms)`));
      }
    }, timeoutMs);

    connectReq.on('connect', (res, socket) => {
      if (res.statusCode !== 200) {
        finished = true;
        clearTimeout(timer);
        socket.destroy();
        return reject(new Error(`Proxy CONNECT failed with status: ${res.statusCode}`));
      }

      const tlsReq = https.request({
        host: targetHost,
        path: reqPath,
        method,
        socket,
        headers: {
          ...headers,
          'Content-Length': Buffer.byteLength(body),
        },
        timeout: timeoutMs,
      }, (tlsRes) => {
        let respData = '';
        tlsRes.on('data', chunk => { respData += chunk; });
        tlsRes.on('end', () => {
          finished = true;
          clearTimeout(timer);
          resolve({ statusCode: tlsRes.statusCode, body: respData });
        });
      });

      tlsReq.on('error', (err) => {
        if (!finished) {
          finished = true;
          clearTimeout(timer);
          reject(err);
        }
      });

      tlsReq.write(body);
      tlsReq.end();
    });

    connectReq.on('error', (err) => {
      if (!finished) {
        finished = true;
        clearTimeout(timer);
        reject(err);
      }
    });

    connectReq.end();
  });
}

/**
 * 视觉分析核心方法：提取视频画面中相公的穿搭、神态与环境
 * @param {Object} params
 * @param {string} params.imageBase64 纯 base64 字符串（不带 data:image 前缀或带均可）
 * @param {string} [params.mimeType='image/jpeg']
 * @returns {Promise<string|null>} 提炼出的中文视觉描述
 */
export async function analyzeVisualFrame({ imageBase64, mimeType = 'image/jpeg' }) {
  if (!imageBase64 || typeof imageBase64 !== 'string') return null;

  const cfg = readVisionConfig();
  if (!cfg.apiKey || cfg.enabled === false) return null;

  const cleanBase64 = imageBase64.includes(',') ? imageBase64.split(',')[1] : imageBase64;
  const proxy = cfg.proxy || 'http://127.0.0.1:27890';
  const modelsToTry = [cfg.model || 'gemini-3.5-flash', 'gemini-3.6-flash', 'gemini-3.7-flash'];

  const promptText = '这是视频通话中对方（相公）的一帧画面。请用1-2句话客观描述相公的面部神态（如是否微笑、眼神、表情）、发型穿搭（衣服颜色与款式）、当前动作或手中拿的物品，以及身后的房间环境。只输出简明真实事实，切勿添加客套话，供伴侣回应参考。';

  const payload = JSON.stringify({
    contents: [
      {
        parts: [
          {
            inlineData: {
              mimeType,
              data: cleanBase64.trim(),
            },
          },
          {
            text: promptText,
          },
        ],
      },
    ],
  });

  for (const model of modelsToTry) {
    try {
      const res = await requestViaProxy({
        proxyUrl: proxy,
        targetHost: 'generativelanguage.googleapis.com',
        path: `/v1beta/models/${model}:generateContent`,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-goog-api-key': cfg.apiKey,
        },
        body: payload,
        timeoutMs: 6500,
      });

      if (res.statusCode === 200) {
        const data = JSON.parse(res.body);
        const text = data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
        if (text) return text;
      }
    } catch (_) {
      // 尝试下一个模型
    }
  }

  return null;
}

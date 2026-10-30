import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * 查找可用的 Edge-TTS 执行器路径
 * 优先级：
 * 1. 本地打包好的绿色免安装独立可执行程序 (edge-tts.exe)
 * 2. 小主机/系统路径下的 edge-tts
 * 3. python -m edge_tts 模块
 */
export function findEdgeTtsBinary() {
  const candidates = [
    // 相对 src/ 目录
    path.join(__dirname, '../tools/dist/edge-tts/edge-tts.exe'),
    path.join(__dirname, '../edge-tts/edge-tts.exe'),
    path.join(__dirname, 'edge-tts/edge-tts.exe'),
    path.join(__dirname, '../bin/edge-tts.exe'),
    path.join(process.cwd(), 'tools/dist/edge-tts/edge-tts.exe'),
    path.join(process.cwd(), 'edge-tts/edge-tts.exe'),
  ];

  for (const p of candidates) {
    try {
      if (fs.existsSync(p) && fs.statSync(p).isFile()) {
        return { type: 'exe', path: p };
      }
    } catch {}
  }

  return { type: 'cmd', path: 'edge-tts' };
}

function cleanVoiceText(text) {
  return String(text ?? '')
    .replace(/\[(compare|image|music|sticker|card):[^\]]*\]/gi, '')
    .replace(/\[\s*emoji[:_][^\]]+\]/gi, '')
    .replace(/\{\s*emoji[:_][^\}]+\}/gi, '')
    .replace(/\bemoji[:_][a-zA-Z0-9_-]+/gi, '')
    .replace(/\[[^\]]{1,50}\]/g, '')
    .replace(/【[^】]{1,50}】/g, '')
    .replace(/[（(][^）)]{1,50}[）)]/g, '')
    .replace(/\*[^*]{1,50}\*/g, '')
    .replace(/~[^~]{1,30}~/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .replace(/，\s*，/g, '，')
    .trim();
}

/**
 * 使用微软 Edge 神经网络女声合成音频
 * @param {Object} options
 * @param {string} options.text 待合成文本
 * @param {string} [options.voice='zh-CN-XiaoxiaoNeural'] 神经网络音色
 * @param {string} options.outFile 输出音频文件路径
 * @param {number} [options.timeoutMs=15000] 超时时间（默认15秒）
 * @returns {Promise<{path: string, durationMs: number, size: number}>}
 */
export function synthesizeEdgeTts({
  text,
  voice = 'zh-CN-XiaoxiaoNeural',
  rate = '-12%',
  pitch = '+2Hz',
  outFile,
  timeoutMs = 15000,
}) {
  return new Promise((resolve, reject) => {
    const say = cleanVoiceText(text);
    if (!say) return reject(new Error('待合成内容为空（清洗后无发音文本）'));
    if (!outFile) return reject(new Error('缺少 outFile 输出路径'));

    fs.mkdirSync(path.dirname(outFile), { recursive: true });

    // 使用临时 UTF-8 文本文件传参，彻底根除 Windows 命令行引号、换行与特殊字符崩溃
    const txtFile = `${outFile}.${process.pid}.txt`;
    try {
      fs.writeFileSync(txtFile, say, 'utf8');
    } catch (e) {
      return reject(new Error(`写入临时文本文件失败: ${e.message}`));
    }

    const bin = findEdgeTtsBinary();
    const args = ['--voice', voice, `--rate=${rate}`, `--pitch=${pitch}`, '--file', txtFile, '--write-media', outFile];

    let cmd = bin.path;
    let spawnArgs = args;

    if (bin.type === 'cmd') {
      // 如果没有独立 exe，尝试系统命令
      cmd = process.platform === 'win32' ? 'cmd.exe' : 'edge-tts';
      spawnArgs = process.platform === 'win32' ? ['/c', 'edge-tts', ...args] : args;
    }

    const child = execFile(cmd, spawnArgs, { timeout: timeoutMs, windowsHide: true }, (err, stdout, stderr) => {
      // 无论成败一律清理临时文本文件
      try { if (fs.existsSync(txtFile)) fs.unlinkSync(txtFile); } catch {}

      if (err) {
        const detail = (stderr && stderr.trim()) ? stderr.trim() : (stdout && stdout.trim() ? stdout.trim() : (err.message || String(err)));
        return reject(new Error(`Edge TTS 合成失败: ${detail}`));
      }

      try {
        if (!fs.existsSync(outFile)) {
          return reject(new Error(`Edge TTS 执行完成但未生成文件: ${outFile}`));
        }
        const stat = fs.statSync(outFile);
        if (stat.size < 100) {
          return reject(new Error(`Edge TTS 生成音频异常（文件过小: ${stat.size} 字节）`));
        }

        // MP3 音频约 48kbps = 6000 字节/秒
        const durationMs = Math.max(800, Math.round((stat.size / 6000) * 1000));
        resolve({ path: outFile, durationMs, size: stat.size });
      } catch (e) {
        reject(e);
      }
    });

    child.on('error', (err) => {
      try { if (fs.existsSync(txtFile)) fs.unlinkSync(txtFile); } catch {}
      reject(new Error(`Edge TTS 进程启动失败: ${err.message}`));
    });
  });
}

/**
 * SurfCore · 家庭多角色与独立会话映射服务 (Family Profiles)
 *
 * 核心机制：
 *   单端口 (3088) + 多 Token 分流。
 *   不同家庭成员使用各自手机上的 App，配置专属 Token：
 *     - husband: 专属老婆人设，对话记录隔离为 history-husband.json
 *     - wife:    贴心大管家人设，对话记录隔离为 history-wife.json
 *     - son:     全能探索导师人设，对话记录隔离为 history-son.json
 *
 * 保证：
 *   1. 物理级数据隔离，绝不串台，聊天记录各存各的；
 *   2. 移动端 App 零修改，直接通过现有 Token 字段自动识别；
 *   3. 绝对向下兼容：默认主 host-token 自动归属 husband。
 */
import fs from 'node:fs';
import path from 'node:path';
import { QQ_PERSONA_DIR } from './paths.js';

const PROFILES_FILE_NAME = 'family-tokens.json';

export function createFamilyProfileManager({ rootDir, defaultTokenGetter = () => '' } = {}) {
  const file = path.join(rootDir, PROFILES_FILE_NAME);

  function defaultProfiles() {
    const mainToken = String(defaultTokenGetter() || '').trim();
    return {
      version: 1,
      profiles: {
        husband: {
          key: 'husband',
          token: mainToken,
          name: '专属老婆',
          personaFile: path.join(QQ_PERSONA_DIR, '傲娇助手.md'),
          historyId: 'husband',
          description: '老公的专属小娇妻，千依百顺、温柔体贴、无话不谈',
        },
        wife: {
          key: 'wife',
          token: 'wife-token-8888',
          name: '贴心大管家',
          personaFile: path.join(QQ_PERSONA_DIR, '贴心管家.md'),
          historyId: 'wife',
          description: '女主人的专属管家，高情商倾听、生活百事通、情绪价值拉满',
        },
        son: {
          key: 'son',
          token: 'son-token-9999',
          name: '全能探索导师',
          personaFile: path.join(QQ_PERSONA_DIR, '全能导师.md'),
          historyId: 'son',
          description: '孩子的学霸大哥哥与探索导师，幽默风趣、科学百科、启发式耐心辅导',
        },
      },
    };
  }

  function readProfiles() {
    const mainToken = String(defaultTokenGetter() || '').trim();
    try {
      if (fs.existsSync(file)) {
        const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
        if (raw?.profiles && typeof raw.profiles === 'object') {
          // 确保 husband 的 token 始终能兼容当前主 token
          if (mainToken && !raw.profiles.husband?.token) {
            raw.profiles.husband = {
              ...(raw.profiles.husband || {}),
              key: 'husband',
              token: mainToken,
              name: raw.profiles.husband?.name || '专属老婆',
              personaFile: raw.profiles.husband?.personaFile || path.join(QQ_PERSONA_DIR, '傲娇助手.md'),
              historyId: 'husband',
            };
          }
          return raw.profiles;
        }
      }
    } catch {}

    const init = defaultProfiles();
    try {
      fs.mkdirSync(rootDir, { recursive: true });
      fs.writeFileSync(file, `${JSON.stringify(init, null, 2)}\n`, 'utf8');
    } catch {}
    return init.profiles;
  }

  function resolveProfile(tokenOrKey) {
    const str = String(tokenOrKey || '').trim();
    if (!str) return null;
    const profiles = readProfiles();
    const mainToken = String(defaultTokenGetter() || '').trim();

    // 0. 直接通过 key 查找 (husband, wife, son)
    if (profiles[str]) {
      return { ...profiles[str], key: str };
    }

    // 1. 优先匹配配置里的具体 profile 的 token
    for (const [key, p] of Object.entries(profiles)) {
      if (p.token && p.token === str) {
        return { ...p, key };
      }
    }

    // 2. 如果等于主 token，归属到 husband
    if (mainToken && str === mainToken) {
      return profiles.husband ? { ...profiles.husband, key: 'husband' } : {
        key: 'husband',
        token: mainToken,
        name: '专属老婆',
        personaFile: path.join(QQ_PERSONA_DIR, '傲娇助手.md'),
        historyId: 'husband',
      };
    }

    return null;
  }

  return {
    file,
    readProfiles,
    resolveProfile,
  };
}

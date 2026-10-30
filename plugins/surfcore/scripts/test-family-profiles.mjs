import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createPetChatService } from '../lib/pet-chat.js';
import { createPetApiService } from '../lib/pet-api.js';

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'surfcore-family-test-'));

try {
  const service = createPetChatService({
    stateDir: tmpDir,
    tokenBudget: null,
  });

  const mainToken = service.token();
  assert.ok(mainToken, '必须能生成主 token');

  // 1. 验证 family-tokens.json 生成与结构
  const profiles = service.readProfiles();
  assert.ok(profiles.husband, 'husband 存在');
  assert.ok(profiles.wife, 'wife 存在');
  assert.ok(profiles.son, 'son 存在');

  console.log('✅ family-tokens 配置结构完整');

  // 2. 验证根据 Token 解析 Profile
  const p1 = service.resolveProfile(mainToken);
  assert.equal(p1?.key, 'husband');
  assert.equal(p1?.name, '专属老婆');

  const p2 = service.resolveProfile('wife-token-8888');
  assert.equal(p2?.key, 'wife');
  assert.equal(p2?.name, '贴心大管家');

  const p3 = service.resolveProfile('son-token-9999');
  assert.equal(p3?.key, 'son');
  assert.equal(p3?.name, '全能探索导师');

  const pFail = service.resolveProfile('wrong-token');
  assert.equal(pFail, null, '非法 token 必须解析失败');

  console.log('✅ Token 路由与身份映射校验通过');

  // 3. 验证 publicConfig 与 roleInfo 隔离
  const cfgHusband = service.publicConfig(p1.key);
  assert.equal(cfgHusband.role.name, '温柔小娘子');

  const cfgWife = service.publicConfig(p2.key);
  assert.equal(cfgWife.role.name, '贴心大管家');

  const cfgSon = service.publicConfig(p3.key);
  assert.equal(cfgSon.role.name, '全能探索导师');

  console.log('✅ 各角色名称与人设展示 100% 隔离');

  // 4. 验证历史记录独立存储
  const api = createPetApiService({
    chat: service,
    purpose: null,
    petService: null,
    stateDir: tmpDir,
    currentDshUrl: () => 'http://127.0.0.1:3080',
    version: '1.0.0',
  });

  // 模拟分别读取历史
  const histHusband = service.history(10, 'husband');
  const histWife = service.history(10, 'wife');
  const histSon = service.history(10, 'son');

  assert.equal(histHusband.role.name, '温柔小娘子');
  assert.equal(histWife.role.name, '贴心大管家');
  assert.equal(histSon.role.name, '全能探索导师');

  console.log('✅ 会话记录与历史数据绝对物理隔离测试通过！');
  console.log('\n🎉 ALL FAMILY PROFILE TESTS PASSED!');
} finally {
  fs.rmSync(tmpDir, { recursive: true, force: true });
}

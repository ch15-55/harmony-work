#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v1.2 美化：为二级页面批量插入 pageTransition() 转场方法。
- 普通二级页：右侧滑入（Push 进 / Pop 退）
- RecordEditPage：底部滑入（模态编辑感）
- Index（Tabs 根页）：被覆盖时轻微视差左移
幂等：已含 pageTransition 的文件跳过。
"""
import io
import os
import re
import sys

PAGES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                         'harmony', 'entry', 'src', 'main', 'ets', 'pages')

RIGHT_METHOD = '''
  /** 页面转场：二级页统一右侧滑入（v1.2 美化） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 300, curve: Curve.EaseOut })
      .slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .slide(SlideEffect.Right)
  }
'''

BOTTOM_METHOD = '''
  /** 页面转场：底部滑入，模态编辑感（v1.2 美化） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 320, curve: Curve.EaseOut })
      .slide(SlideEffect.Bottom)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .slide(SlideEffect.Bottom)
  }
'''

ROOT_METHOD = '''
  /** 页面转场：被二级页覆盖时轻微视差左移（v1.2 美化，呼应二级页右滑入） */
  pageTransition() {
    PageTransitionExit({ type: RouteType.Push, duration: 300, curve: Curve.EaseOut })
      .translate({ x: '-10%' })
    PageTransitionEnter({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .translate({ x: '0%' })
  }
'''

RIGHT_PAGES = [
    'AboutPage.ets', 'AccountEditPage.ets', 'AccountManagePage.ets',
    'AppLockSettingPage.ets', 'BackupPage.ets', 'BudgetSettingPage.ets',
    'CategoryManagePage.ets', 'CategoryTxListPage.ets', 'DiagnosticsPage.ets',
    'ExportPage.ets', 'LedgerManagePage.ets', 'PinVerifyPage.ets',
    'PrivacyPage.ets', 'PrivacyPolicyPage.ets', 'ThemeSettingPage.ets',
    'TransactionDetailPage.ets', 'UserAgreementPage.ets',
]

# 匹配 "@Entry\n@Component\n(export )?struct NAME {" 的结构声明行
STRUCT_RE = re.compile(
    r'(@Entry\s*\n@Component\s*\n(?:export\s+)?struct\s+\w+\s*\{)')


def insert_method(path: str, method: str) -> bool:
    with io.open(path, 'r', encoding='utf-8', newline='') as f:
        content = f.read()
    if 'pageTransition' in content:
        print('SKIP (already has pageTransition): ' + os.path.basename(path))
        return False
    m = STRUCT_RE.search(content)
    if not m:
        print('WARN (struct decl not found): ' + os.path.basename(path))
        return False
    new_content = content[:m.end()] + method + content[m.end():]
    with io.open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(new_content)
    print('OK: ' + os.path.basename(path))
    return True


def main() -> int:
    changed = 0
    for name in RIGHT_PAGES:
        p = os.path.join(PAGES_DIR, name)
        if not os.path.isfile(p):
            print('MISSING: ' + name)
            continue
        if insert_method(p, RIGHT_METHOD):
            changed += 1
    # 记账页：底部滑入
    rec = os.path.join(PAGES_DIR, 'RecordEditPage.ets')
    if os.path.isfile(rec) and insert_method(rec, BOTTOM_METHOD):
        changed += 1
    # 根页：视差
    idx = os.path.join(PAGES_DIR, 'Index.ets')
    if os.path.isfile(idx) and insert_method(idx, ROOT_METHOD):
        changed += 1
    print('changed files: %d' % changed)
    return 0


if __name__ == '__main__':
    sys.exit(main())

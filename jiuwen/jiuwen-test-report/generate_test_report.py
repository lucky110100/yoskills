# -*- coding: utf-8 -*-
import os, re, sys, xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

PROJECT_ROOT = Path(os.environ.get('PROJECT_ROOT', r'D:\jiuwen\main'))
TEST_DIR = os.environ.get('TEST_DIR', 'JiuwenTestJava')
CASE_SCOPE = os.environ.get('CASE_SCOPE', 'smoke')
OUTPUT = Path(os.environ.get('OUTPUT', str(PROJECT_ROOT / 'output' / datetime.now().strftime('%Y%m%d'))))
SUREFIRE_DIR = PROJECT_ROOT / TEST_DIR / 'target' / 'surefire-reports'
OUTPUT.mkdir(parents=True, exist_ok=True)
OUTPUT_FILE = OUTPUT / ('test_results_' + datetime.now().strftime('%Y%m%d_%H%M%S') + '.xlsx')

# ------ Priority keywords (case-insensitive match) ------
P1_KEYWORDS = ['python contract', 'fake-green guard', 'blocked sdk parity', 'sdk not implemented', 'parity gap', 'unsupportedoperationexception', 'noclassdeffounderror', 'not yet implemented']
P2_KEYWORDS = ['instead of', 'result map contains extra', 'exposes a different', 'chunk wrapping', 'classcastexception', 'expecting code to raise a throwable', 'expecting the throwable to be', 'but got', 'extra key']
P3_KEYWORDS = ['pytest.mark.skip', 'real llm', 'real model', 'requires llm endpoint', 'pending real llm', 'api_key', 'test_api_key', 'tavily_key', 'connection refused', 'unknownhostexception', 'pytest is skipped', 'deferred', 'extra java/support: local smoke', 'python source is skipped', 'python tests skipped']

def classify_priority(st, msg, tp, tx):
    'Full P0-P4 classification per SKILL.md rules.'
    if st == 'passed': return 'P4'
    text = (msg + ' ' + tp + ' ' + (tx or '')).lower()
    if st == 'skipped':
        if any(k in text for k in P3_KEYWORDS): return 'P3'
        if any(k in text for k in P2_KEYWORDS): return 'P2'
        if any(k in text for k in P1_KEYWORDS): return 'P1'
        return 'P3'
    if any(k in text for k in P1_KEYWORDS): return 'P1'
    if any(k in text for k in P2_KEYWORDS): return 'P2'
    if any(k in text for k in P3_KEYWORDS): return 'P3'
    return 'P0'

def extract_module_name(cn):
    parts = cn.split('.')
    try: idx = parts.index('cases')
    except ValueError: return cn
    rest = parts[idx+1:]
    return rest[0] if rest else cn

def extract_case_dir(cn):
    parts = cn.split('.')
    try: idx = parts.index('cases')
    except ValueError: return '-'
    rest = parts[idx+1: -1]
    return '/'.join(rest) if rest else '-'

def extract_testcase_filename(cn, tn):
    return cn.split('.')[-1] + '.java'

def truncate_msg(msg, limit=200):
    if not msg: return ''
    return (msg[:limit] + '...') if len(msg) > limit else msg

def parse_surefire_reports(sd):
    rows = []
    for xf in sorted(sd.glob('TEST-*.xml')):
        try: root = ET.parse(str(xf)).getroot()
        except: continue
        for tc in root.iter('testcase'):
            cn = tc.get('classname','')
            tn = tc.get('name','')
            st = 'passed'; msg = ''; tp = ''; tx = ''
            fe = tc.find('failure'); ee = tc.find('error'); se = tc.find('skipped')
            if fe is not None:
                st = 'failed'; msg = fe.get('message','') or ''
                tp = fe.get('type','') or ''; tx = fe.text or ''
            elif ee is not None:
                st = 'error'; msg = ee.get('message','') or ''
                tp = ee.get('type','') or ''; tx = ee.text or ''
            elif se is not None:
                st = 'skipped'; msg = se.get('message','') or ''
            pr = classify_priority(st, msg, tp, tx)
            rows.append({'module':extract_module_name(cn),
                         'filename':extract_testcase_filename(cn,tn),
                         'status':st,
                         'priority':pr,
                         'message':truncate_msg(msg),
                         'case_dir':extract_case_dir(cn)})
    return rows

def print_summary(rows):
    if not rows: print('No results.'); return
    t = len(rows); p = sum(1 for r in rows if r['status']=='passed')
    f = sum(1 for r in rows if r['status']=='failed')
    e = sum(1 for r in rows if r['status']=='error')
    s = sum(1 for r in rows if r['status']=='skipped')
    print(f'总计: {t}  通过: {p}  失败: {f}  错误: {e}  跳过: {s}')
    print('优先级分布:')
    for pr in ['P0','P1','P2','P3','P4']:
        cnt = sum(1 for r in rows if r['priority']==pr)
        print(f'  {pr}: {cnt}')

def gen_excel(rows, op):
    wb = Workbook()
    ws = wb.active
    ws.title = 'Test Report'
    headers = ['模块名', '用例文件名', '状态', '优先级', '不通过原因', '用例目录']
    hdr_font = Font(bold=True, color='FFFFFF', size=11)
    hdr_fill = PatternFill(start_color='1F4E79', end_color='1F4E79', fill_type='solid')
    hdr_align = Alignment(horizontal='center', vertical='center', wrap_text=True)
    thin_border = Border(left=Side(style='thin'), right=Side(style='thin'), top=Side(style='thin'), bottom=Side(style='thin'))
    pr_fills = {
        'P0': PatternFill(start_color='F4A460', end_color='F4A460', fill_type='solid'),
        'P1': PatternFill(start_color='FFD700', end_color='FFD700', fill_type='solid'),
        'P2': PatternFill(start_color='FFFACD', end_color='FFFACD', fill_type='solid'),
        'P3': PatternFill(start_color='ADD8E6', end_color='ADD8E6', fill_type='solid'),
        'P4': PatternFill(start_color='90EE90', end_color='90EE90', fill_type='solid'),
    }
    for c, h in enumerate(headers, 1):
        cell = ws.cell(row=1, column=c, value=h)
        cell.font = hdr_font; cell.fill = hdr_fill; cell.alignment = hdr_align; cell.border = thin_border
    for i, r in enumerate(rows, 2):
        ws.cell(row=i, column=1, value=r['module']).border = thin_border
        ws.cell(row=i, column=2, value=r['filename']).border = thin_border
        st_cn = {'passed':'通过','failed':'失败','error':'错误','skipped':'跳过'}.get(r['status'], r['status'])
        st_cell = ws.cell(row=i, column=3, value=st_cn); st_cell.border = thin_border
        pr_cell = ws.cell(row=i, column=4, value=r['priority'])
        pr_cell.fill = pr_fills.get(r['priority'], PatternFill()); pr_cell.border = thin_border
        pr_cell.alignment = Alignment(horizontal='center')
        ws.cell(row=i, column=5, value=r['message']).border = thin_border
        ws.cell(row=i, column=6, value=r['case_dir']).border = thin_border
    ws.freeze_panes = 'A2'
    for col_idx in range(1, 7):
        max_len = len(str(ws.cell(row=1, column=col_idx).value))
        for row_idx in range(2, min(len(rows)+2, 200)):
            v = ws.cell(row=row_idx, column=col_idx).value
            if v: max_len = max(max_len, min(len(str(v)), 60))
        ws.column_dimensions[ws.cell(row=1, column=col_idx).column_letter].width = max_len + 3

    ws2 = wb.create_sheet('Summary')
    ws2.cell(row=1, column=1, value='总用例数').font = Font(bold=True)
    ws2.cell(row=1, column=2, value=len(rows))
    statuses = {'通过': sum(1 for r in rows if r['status']=='passed'),
               '失败': sum(1 for r in rows if r['status']=='failed'),
               '错误': sum(1 for r in rows if r['status']=='error'),
               '跳过': sum(1 for r in rows if r['status']=='skipped')}
    for j, (k, v) in enumerate(statuses.items(), 2):
        ws2.cell(row=j, column=1, value=k); ws2.cell(row=j, column=2, value=v)
    ws2.cell(row=len(statuses)+2, column=1, value='优先级').font = Font(bold=True)
    ws2.cell(row=len(statuses)+2, column=2, value='数量').font = Font(bold=True)
    for j, pr in enumerate(['P0','P1','P2','P3','P4'], len(statuses)+3):
        cnt = sum(1 for r in rows if r['priority']==pr)
        ws2.cell(row=j, column=1, value=pr)
        c2 = ws2.cell(row=j, column=2, value=cnt)
        c2.fill = pr_fills.get(pr, PatternFill())
    ws2.column_dimensions['A'].width = 15; ws2.column_dimensions['B'].width = 12

    wb.save(str(op))
    print(f'Saved: {op} ({op.stat().st_size:+,} bytes)')

def main():
    if not SUREFIRE_DIR.exists():
        print(f'ERROR: surefire-reports dir not found: {SUREFIRE_DIR}', file=sys.stderr); sys.exit(2)
    xml = sorted(SUREFIRE_DIR.glob('TEST-*.xml'))
    print(f'XML files found: {len(xml)}')
    rows = parse_surefire_reports(SUREFIRE_DIR)
    print(f'Test cases parsed: {len(rows)}')
    print_summary(rows)
    gen_excel(rows, OUTPUT_FILE)

if __name__ == '__main__': main()

#!/usr/bin/env python3
"""
飞书云文档推送脚本
读取日报 Markdown 文件，创建飞书云文档并写入内容，返回文档链接。

用法: python3 feishu_doc_push.py <report_file> <date>
输出: 文档 URL（成功时）

配置来源（按优先级）：
1. 环境变量 FEISHU_APP_ID / FEISHU_APP_SECRET
2. ~/.claude/hooks/config.sh 中的同名变量
"""

import sys
import os
import json
import re
import time
import urllib.request
import urllib.error

# ─── 加载配置 ──────────────────────────────────────────

def load_config():
    """从环境变量或 config.sh 加载飞书凭证"""
    app_id = os.environ.get("FEISHU_APP_ID", "")
    app_secret = os.environ.get("FEISHU_APP_SECRET", "")

    if not app_id or not app_secret:
        # 尝试从 config.sh 读取
        config_path = os.path.expanduser("~/.claude/hooks/config.sh")
        if os.path.exists(config_path):
            with open(config_path) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("#") or "=" not in line:
                        continue
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.strip().strip('"').strip("'")
                    if key == "FEISHU_APP_ID" and not app_id:
                        app_id = val
                    elif key == "FEISHU_APP_SECRET" and not app_secret:
                        app_secret = val

    if not app_id or not app_secret:
        print("错误: 未配置 FEISHU_APP_ID 或 FEISHU_APP_SECRET", file=sys.stderr)
        print("请在 ~/.claude/hooks/config.sh 或环境变量中设置", file=sys.stderr)
        sys.exit(1)

    return app_id, app_secret


APP_ID, APP_SECRET = load_config()
BASE_URL = "https://open.feishu.cn/open-apis"


def api_request(method, path, token=None, body=None):
    """发送飞书 API 请求"""
    url = f"{BASE_URL}{path}"
    data = json.dumps(body).encode("utf-8") if body else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="ignore")
        print(f"API 错误 [{e.code}]: {error_body}", file=sys.stderr)
        return None


def get_tenant_token():
    """获取 tenant_access_token"""
    resp = api_request("POST", "/auth/v3/tenant_access_token/internal", body={
        "app_id": APP_ID,
        "app_secret": APP_SECRET,
    })
    if resp and resp.get("code") == 0:
        return resp["tenant_access_token"]
    print(f"获取 token 失败: {resp}", file=sys.stderr)
    return None


def parse_markdown_to_blocks(md_text):
    """将 Markdown 文本转换为飞书文档 block 结构"""
    blocks = []
    lines = md_text.split("\n")
    i = 0

    while i < len(lines):
        line = lines[i]

        if not line.strip():
            i += 1
            continue

        if re.match(r"^---+\s*$", line):
            blocks.append({"block_type": 22, "divider": {}})
            i += 1
            continue

        heading_match = re.match(r"^(#{1,9})\s+(.*)", line)
        if heading_match:
            level = len(heading_match.group(1))
            text = heading_match.group(2)
            block_type = min(level + 2, 11)
            block_key = f"heading{min(level, 9)}"
            blocks.append({
                "block_type": block_type,
                block_key: {"elements": parse_inline_elements(text)}
            })
            i += 1
            continue

        if re.match(r"^[-*+]\s+", line):
            items = []
            while i < len(lines) and re.match(r"^[-*+]\s+", lines[i]):
                item_text = re.sub(r"^[-*+]\s+", "", lines[i])
                items.append(item_text)
                i += 1
            for item in items:
                blocks.append({
                    "block_type": 12,
                    "bullet": {"elements": parse_inline_elements(item)}
                })
            continue

        if re.match(r"^\d+\.\s+", line):
            items = []
            while i < len(lines) and re.match(r"^\d+\.\s+", lines[i]):
                item_text = re.sub(r"^\d+\.\s+", "", lines[i])
                items.append(item_text)
                i += 1
            for item in items:
                blocks.append({
                    "block_type": 13,
                    "ordered": {"elements": parse_inline_elements(item)}
                })
            continue

        if re.match(r"^\|", line):
            table_lines = []
            while i < len(lines) and re.match(r"^\|", lines[i]):
                if re.match(r"^\|[\s-]+\|", lines[i]):
                    i += 1
                    continue
                table_lines.append(lines[i])
                i += 1
            if table_lines:
                blocks.extend(build_table_blocks(table_lines))
            continue

        blocks.append({
            "block_type": 2,
            "text": {"elements": parse_inline_elements(line)}
        })
        i += 1

    return blocks


def parse_inline_elements(text):
    """解析行内格式为飞书 text_run 元素列表"""
    elements = []
    pattern = r"(\*\*(.+?)\*\*|`(.+?)`)"
    last_end = 0

    for m in re.finditer(pattern, text):
        if m.start() > last_end:
            plain = text[last_end:m.start()]
            if plain:
                elements.append({"text_run": {"content": plain}})

        if m.group(2):
            elements.append({
                "text_run": {
                    "content": m.group(2),
                    "text_element_style": {"bold": True}
                }
            })
        elif m.group(3):
            elements.append({
                "text_run": {
                    "content": m.group(3),
                    "text_element_style": {"inline_code": True}
                }
            })

        last_end = m.end()

    if last_end < len(text):
        remaining = text[last_end:]
        if remaining:
            elements.append({"text_run": {"content": remaining}})

    if not elements:
        elements.append({"text_run": {"content": text}})

    return elements


def build_table_blocks(table_lines):
    """将表格行转换为飞书文本 block"""
    blocks = []
    rows = []
    for line in table_lines:
        cells = [c.strip() for c in line.strip("|").split("|")]
        rows.append(cells)

    if not rows:
        return blocks

    col_count = max(len(r) for r in rows)
    col_widths = [0] * col_count
    for row in rows:
        for j, cell in enumerate(row):
            if j < col_count:
                col_widths[j] = max(col_widths[j], len(cell))

    lines = []
    for idx, row in enumerate(rows):
        padded = []
        for j in range(col_count):
            cell = row[j] if j < len(row) else ""
            padded.append(cell.ljust(col_widths[j]))
        lines.append(" | ".join(padded))
        if idx == 0:
            lines.append(" | ".join("-" * w for w in col_widths))

    table_text = "\n".join(lines)
    blocks.append({
        "block_type": 2,
        "text": {"elements": [{"text_run": {"content": table_text}}]}
    })

    return blocks


def create_document(token, title):
    """创建飞书云文档"""
    resp = api_request("POST", "/docx/v1/documents", token=token, body={
        "title": title,
    })
    if resp and resp.get("code") == 0:
        doc = resp["data"]["document"]
        return doc["document_id"]
    print(f"创建文档失败: {resp}", file=sys.stderr)
    return None


def write_blocks_to_document(token, doc_id, blocks):
    """将 blocks 写入文档（分批，每次最多 50 个 block）"""
    BATCH_SIZE = 50
    root_block_id = doc_id

    for start in range(0, len(blocks), BATCH_SIZE):
        batch = blocks[start:start + BATCH_SIZE]
        resp = api_request(
            "POST",
            f"/docx/v1/documents/{doc_id}/blocks/{root_block_id}/children",
            token=token,
            body={"children": batch}
        )
        if not resp or resp.get("code") != 0:
            print(f"写入 block 失败 (batch {start}): {resp}", file=sys.stderr)
            return False
        if start + BATCH_SIZE < len(blocks):
            time.sleep(0.3)

    return True


def set_link_share_readable(token, doc_id):
    """设置文档为链接可读（组织内）"""
    resp = api_request(
        "PATCH",
        f"/drive/v1/permissions/{doc_id}/public?type=docx",
        token=token,
        body={
            "external_access_entity": "open",
            "security_entity": "anyone_can_view",
            "comment_entity": "anyone_can_view",
            "share_entity": "anyone",
            "link_share_entity": "anyone_readable",
        }
    )
    if resp and resp.get("code") == 0:
        return True
    print(f"设置链接分享失败（非致命）: {resp}", file=sys.stderr)
    return False


def main():
    if len(sys.argv) < 3:
        print("用法: python3 feishu_doc_push.py <report_file> <date>", file=sys.stderr)
        sys.exit(1)

    report_file = sys.argv[1]
    date_str = sys.argv[2]

    if not os.path.exists(report_file):
        print(f"文件不存在: {report_file}", file=sys.stderr)
        sys.exit(1)

    with open(report_file, "r", encoding="utf-8") as f:
        md_content = f.read()

    if not md_content.strip():
        print("日报内容为空", file=sys.stderr)
        sys.exit(1)

    token = get_tenant_token()
    if not token:
        sys.exit(1)

    title = f"工作日报 - {date_str}"
    doc_id = create_document(token, title)
    if not doc_id:
        sys.exit(1)

    blocks = parse_markdown_to_blocks(md_content)
    if not blocks:
        print("解析 Markdown 后无内容", file=sys.stderr)
        sys.exit(1)

    success = write_blocks_to_document(token, doc_id, blocks)
    if not success:
        sys.exit(1)

    set_link_share_readable(token, doc_id)

    doc_url = f"https://feishu.cn/docx/{doc_id}"
    print(doc_url)


if __name__ == "__main__":
    main()

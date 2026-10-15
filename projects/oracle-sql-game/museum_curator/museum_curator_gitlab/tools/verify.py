"""Общая статическая проверка проекта: смотрит код, не запуская базу."""
import io, re, glob, os, sys
from pathlib import Path

ROOT = str(Path(__file__).resolve().parent.parent)
FAILS, WARNS = [], []

def ok(title, good, note=""):
    mark = "  OK  " if good else " ПРОВАЛ"
    print(f"{mark}  {title}" + (f"   [{note}]" if note else ""))
    if not good:
        FAILS.append(title + (f" — {note}" if note else ""))

def warn(title, note):
    print(f"  ВНИМ  {title}   [{note}]")
    WARNS.append(f"{title} — {note}")

def strip(src):
    """Убрать комментарии и строковые литералы, сохранив позиции."""
    out, i, n = [], 0, len(src)
    while i < n:
        ch = src[i]
        if ch == "'":
            j = i
            i += 1
            while i < n:
                if src[i] == "'":
                    if i + 1 < n and src[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            out.append(" " * (i - j))
        elif ch == "-" and i + 1 < n and src[i + 1] == "-":
            j = i
            while i < n and src[i] != "\n":
                i += 1
            out.append(" " * (i - j))
        else:
            out.append(ch)
            i += 1
    return "".join(out)

R = lambda p: io.open(os.path.join(ROOT, p), encoding="utf-8").read()

spec = R("sql/04_package_spec.sql")
body = R("sql/05_package_body.sql")
ddl = R("sql/01_tables.sql")
seed = R("sql/02_reference_data.sql")
catalog = R("sql/03_catalog_data.sql")
drop = R("sql/00_drop_all.sql")
clean = strip(body)

print("=" * 72)
print(" 1. СТРУКТУРА ПАКЕТА PL/SQL")
print("=" * 72)

c = lambda p, t=clean: len(re.findall(p, t, re.I))
ei, el, ec = c(r"\bEND\s+IF\b"), c(r"\bEND\s+LOOP\b"), c(r"\bEND\s+CASE\b")
plain = c(r"\bEND\b") - ei - el - ec
beg = c(r"\bBEGIN\b")
case_expr = c(r"\bCASE\b") - 2 * ec
n_if = c(r"\bIF\b") - ei
n_loop = c(r"\bLOOP\b") - el
ok("баланс IF / END IF", n_if == ei, "%d/%d" % (n_if, ei))
ok("баланс LOOP / END LOOP", n_loop == el, "%d/%d" % (n_loop, el))
ok("баланс BEGIN / END", plain == beg + case_expr, f"{beg} / {plain}")

decl = lambda t: {m.group(2).lower() for m in
                  re.finditer(r"^\s*(PROCEDURE|FUNCTION)\s+([A-Za-z_]\w*)", t, re.M)}
pub, all_body = decl(spec), decl(body)
priv = all_body - pub
ok("всё из спецификации реализовано", not (pub - all_body), str(sorted(pub - all_body)))
print(f"        публичных {len(pub)}, приватных {len(priv)}, всего {len(pub | priv)}")

print()
print("=" * 72)
print(" 2. ЧАСТЫЕ ОШИБКИ КОМПИЛЯЦИИ ORACLE")
print("=" * 72)

BOUND = re.compile(r";|\bBEGIN\b|\bTHEN\b|\bELSE\b|\bLOOP\b|\bDECLARE\b|\bEXCEPTION\b", re.I)
SQLS = re.compile(r"\b(SELECT|INSERT|UPDATE|DELETE|MERGE|OPEN\s+\w+\s+FOR)\b", re.I)
bad = []
for name in sorted(priv):
    for m in re.finditer(r"\b" + name + r"\s*\(", clean, re.I):
        start = 0
        for b in BOUND.finditer(clean, 0, m.start()):
            start = b.end()
        if SQLS.search(clean[start:m.start()]):
            bad.append("%s @ %d" % (name, clean[:m.start()].count("\n") + 1))
ok("приватные функции не вызываются из SQL (PLS-00231)", not bad, "; ".join(bad))

ids = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", ddl))
kw = {"CREATE", "TABLE", "NUMBER", "VARCHAR2", "DATE", "NOT", "NULL", "DEFAULT",
      "CONSTRAINT", "PRIMARY", "KEY", "UNIQUE", "FOREIGN", "REFERENCES", "CHECK",
      "IN", "AND", "OR", "SEQUENCE", "START", "WITH", "INCREMENT", "BY", "NOCACHE",
      "INDEX", "ON", "CLOB", "SYSDATE"}
longest = max((len(i.encode()), i) for i in ids if i.upper() not in kw)
ok("идентификаторы влезают в предел Oracle 12.2 (128 байт)", longest[0] <= 128,
   f"{longest[1]} = {longest[0]} байт")

print()
print("=" * 72)
print(" 3. СХЕМА И ССЫЛКИ")
print("=" * 72)

tables, order = {}, []
for m in re.finditer(r"CREATE TABLE (\S+) \((.*?)\n\);", ddl, re.S):
    tbl, tbody = m.group(1), m.group(2)
    order.append(tbl.lower())
    cols = set()
    for line in tbody.split("\n"):
        line = line.strip()
        if not line or line.startswith("--") or line.upper().startswith("CONSTRAINT"):
            continue
        mm = re.match(r"([A-Za-z_][\w]*)\s", line)
        if mm:
            cols.add(mm.group(1).lower())
    tables[tbl.lower()] = cols
pos = {t: i for i, t in enumerate(order)}

fwd = []
for m in re.finditer(r"CREATE TABLE (\S+)(.*?)\n\);", ddl, re.S):
    t = m.group(1).lower()
    for ref in re.findall(r"REFERENCES\s+(\S+)\s*\(", m.group(2)):
        if ref.lower() in pos and pos[ref.lower()] > pos[t]:
            fwd.append(f"{t} -> {ref}")
ok("нет ссылок вперёд во внешних ключах", not fwd, "; ".join(fwd))

seqs = {s.lower() for s in re.findall(r"CREATE SEQUENCE (\S+)", ddl)}
ok("у каждой таблицы есть последовательность",
   not [t for t in order if "seq_" + t not in seqs],
   str([t for t in order if "seq_" + t not in seqs]))

listed = {x.lower() for x in re.findall(r"'([A-Z_]+)'", drop)}
ok("все таблицы есть в скрипте очистки",
   not [t for t in order if t not in listed], str([t for t in order if t not in listed]))

used_seq = {s.lower() for s in re.findall(r"(seq_[A-Za-z_]+)\.NEXTVAL", body + seed + catalog)}
ok("все используемые последовательности объявлены",
   not (used_seq - seqs), str(sorted(used_seq - seqs)))

problems = []
for fname in ("sql/02_reference_data.sql", "sql/03_catalog_data.sql",
              "sql/05_package_body.sql"):
    text = re.sub(r"--[^\n]*", "", R(fname))
    for m in re.finditer(r"INSERT\s+INTO\s+([A-Za-z_]\w*)\s*\(([^)]*)\)", text, re.S | re.I):
        t = m.group(1).lower()
        if t in tables:
            for col in m.group(2).split(","):
                col = col.strip().lower()
                if col and col not in tables[t]:
                    problems.append(f"{fname}: {t}.{col}")
    for m in re.finditer(r"UPDATE\s+([A-Za-z_]\w*)\s+(?:\w+\s+)?SET\s+(.*?)(?:\bWHERE\b|\bRETURNING\b|;)",
                         text, re.S | re.I):
        t = m.group(1).lower()
        if t in tables:
            for a in re.split(r",(?![^()]*\))", m.group(2)):
                col = a.split("=")[0].strip().lower()
                if col and re.match(r"^[a-z_]\w*$", col) and col not in tables[t]:
                    problems.append(f"{fname}: {t}.{col}")
ok("все столбцы в INSERT/UPDATE существуют", not problems, "; ".join(sorted(set(problems))[:4]))

print()
print("=" * 72)
print(" 4. СПРАВОЧНЫЕ ЗНАЧЕНИЯ (новая проверка)")
print("=" * 72)

seed_statuses = set(re.findall(r"VALUES \(seq_statuses\.NEXTVAL,'?([^,']+)'?,\s*'([^']+)'", seed))
seed_statuses = {(a.strip().strip("'"), b) for a, b in
                 re.findall(r"seq_statuses\.NEXTVAL,\s*'([^']+)',\s*'([^']+)'", seed)}
used_statuses = set(re.findall(r"f_status\('([^']+)',\s*'([^']+)'\)", body))
missing = used_statuses - seed_statuses
ok("все статусы из кода есть в справочнике",
   not missing, str(sorted(missing)))
print(f"        в справочнике {len(seed_statuses)}, используется в коде {len(used_statuses)}")

def seeded(pattern):
    return set(re.findall(pattern, seed))

checks_literal = [
    ("названия улучшений", r"improvement_name = '([^']+)'",
     seeded(r"seq_improvement_types\.NEXTVAL,\s*'([^']+)'")),
    ("категории посетителей", r"category_name = '([^']+)'",
     seeded(r"seq_visitor_categories\.NEXTVAL,\s*'([^']+)'")),
    ("должности", r"position_name = '([^']+)'",
     seeded(r"seq_positions\.NEXTVAL,\s*'([^']+)'")),
    ("темы", r"theme_name = '([^']+)'",
     seeded(r"seq_themes\.NEXTVAL,\s*'([^']+)'")),
]
for title, pat, available in checks_literal:
    used = set(re.findall(pat, body))
    miss = used - available
    ok(f"{title}: все значения из кода есть в справочнике", not miss,
       f"нет в справочнике: {sorted(miss)}" if miss else f"{len(used)} из {len(available)}")

print()
print("=" * 72)
print(" 5. КЛИЕНТ PYTHON")
print("=" * 72)

# installer.py и check_install.py содержат SQL законно: это установка
# схемы и диагностика, а не игровая логика. Правило «никакого SQL в
# клиенте» относится к игровому коду.
INSTALL_TOOLS = {"installer.py", "check_install.py"}
pyfiles = [f for f in sorted(glob.glob(os.path.join(ROOT, "python", "*.py")))
           if os.path.basename(f) not in INSTALL_TOOLS]
sqlhits = []
for p in pyfiles:
    src = io.open(p, encoding="utf-8").read()
    for m in re.finditer(r"\b(SELECT|INSERT|UPDATE|DELETE|MERGE)\b", src):
        sqlhits.append(os.path.basename(p))
ok("в клиенте нет SQL-операторов", not sqlhits, str(set(sqlhits)))

dbsrc = io.open(os.path.join(ROOT, "python", "db.py"), encoding="utf-8").read()
called = set(re.findall(r'_(?:call|func|rows|one)\(\s*"([a-z_]+)"', dbsrc))
called |= set(re.findall(r'dbms_output\(\s*"([a-z_]+)"', dbsrc))
unknown = {n for n in called if n not in pub}
ok("каждый вызов из db.py есть в спецификации пакета", not unknown, str(sorted(unknown)))
print(f"        клиент зовёт {len(called)} подпрограмм из {len(pub)} публичных")

print()
print("=" * 72)
if FAILS:
    print(f" ИТОГ: ПРОВАЛОВ {len(FAILS)}")
    for f in FAILS:
        print("   - " + f)
    sys.exit(1)
print(" ИТОГ: ВСЕ СТАТИЧЕСКИЕ ПРОВЕРКИ ПРОЙДЕНЫ")
if WARNS:
    print(f" предупреждений: {len(WARNS)}")
print("=" * 72)

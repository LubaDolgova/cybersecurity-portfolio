"""Отслеживает, откуда в клиент пришла каждая строка из базы.

Надо понять, у какого курсора клиент читает тот или иной ключ. Строка
приходит из self.snap("halls"), дальше её передают в метод отрисовки,
перебирают циклом, режут срезом, и где-то далеко внизу читают по
имени столбца. Вот это имя и надо связать с разделом.

Разбираю код как дерево (модуль ast), в несколько проходов:

  1. внутри функции помечаю переменные, которые пришли из
     self.snap("раздел") — прямо, через цикл, срез, enumerate
     или «or []»;
  2. если помеченную переменную передали в метод, помечаю параметр
     этого метода;
  3. повторяю, пока появляются новые пометки.

Что так не проверить: строки, которые пришли в колбэк из фонового
потока. Там связь рвётся об очередь результатов. Это ловит уже
check_runtime.py на живой базе.
"""
from __future__ import annotations

import ast

def snap_section(node: ast.AST) -> str | None:
    """Раздел снимка, если выражение к нему сводится."""
    # self.snap("halls", []) или []
    if isinstance(node, ast.BoolOp):
        for value in node.values:
            found = snap_section(value)
            if found:
                return found
        return None
    # self.snap("events", [])[:3]  и  ...[0]
    if isinstance(node, ast.Subscript):
        return snap_section(node.value)
    # enumerate(self.snap("halls", [])), list(...), reversed(...), sorted(...)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
            and node.func.id in ("enumerate", "list", "reversed", "sorted", "tuple"):
        return snap_section(node.args[0]) if node.args else None
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
        if node.func.attr == "snap" and node.args \
                and isinstance(node.args[0], ast.Constant):
            return node.args[0].value
    return None

def _targets(target: ast.AST) -> list[str]:
    """Имена, которым присваивается значение (включая распаковку)."""
    if isinstance(target, ast.Name):
        return [target.id]
    if isinstance(target, (ast.Tuple, ast.List)):
        out = []
        for element in target.elts:
            out.extend(_targets(element))
        return out
    return []

class Analyzer:
    """Пометки «эта переменная — строка из такого-то курсора»."""

    def __init__(self, source: str, rounds: int = 4):
        self.tree = ast.parse(source)
        self.functions = {
            node.name: node
            for node in ast.walk(self.tree)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        }
        # {имя функции: {имя переменной: раздел}}
        self.local: dict[str, dict[str, str]] = {}
        # {(имя функции, индекс параметра): раздел}
        self.params: dict[tuple[str, int], str] = {}
        for _ in range(rounds):
            if not self._pass():
                break

    def _pass(self) -> bool:
        """Один проход. True, если появились новые пометки."""
        changed = False
        for name, func in self.functions.items():
            marks = dict(self.local.get(name, {}))

            # Пометки, пришедшие через параметры.
            args = [a.arg for a in func.args.args]
            for (fname, index), section in self.params.items():
                if fname == name and index < len(args):
                    if marks.get(args[index]) != section:
                        marks[args[index]] = section
                        changed = True

            # Локальные присваивания и циклы.
            for node in ast.walk(func):
                section = None
                names: list[str] = []
                if isinstance(node, ast.Assign) and len(node.targets) == 1:
                    section = self._section_of(node.value, marks)
                    names = _targets(node.targets[0])
                elif isinstance(node, ast.For):
                    section = self._section_of(node.iter, marks)
                    names = _targets(node.target)
                elif isinstance(node, (ast.ListComp, ast.GeneratorExp, ast.SetComp)):
                    for gen in node.generators:
                        gsection = self._section_of(gen.iter, marks)
                        if gsection:
                            for gname in _targets(gen.target):
                                if marks.get(gname) != gsection:
                                    marks[gname] = gsection
                                    changed = True
                if section:
                    for target_name in names:
                        if marks.get(target_name) != section:
                            marks[target_name] = section
                            changed = True

            self.local[name] = marks

            # Передача помеченного значения в метод.
            for node in ast.walk(func):
                if not isinstance(node, ast.Call):
                    continue
                callee = None
                if isinstance(node.func, ast.Attribute):
                    callee = node.func.attr
                elif isinstance(node.func, ast.Name):
                    callee = node.func.id
                if callee not in self.functions:
                    continue
                target_args = [a.arg for a in self.functions[callee].args.args]
                offset = 1 if target_args and target_args[0] == "self" else 0
                for position, argument in enumerate(node.args):
                    section = self._section_of(argument, marks)
                    if not section:
                        continue
                    key = (callee, position + offset)
                    if self.params.get(key) != section:
                        self.params[key] = section
                        changed = True
        return changed

    def _section_of(self, node: ast.AST, marks: dict[str, str]) -> str | None:
        """Раздел для выражения с учётом уже известных пометок."""
        direct = snap_section(node)
        if direct:
            return direct
        if isinstance(node, ast.Name):
            return marks.get(node.id)
        if isinstance(node, ast.Subscript):
            return self._section_of(node.value, marks)
        if isinstance(node, ast.BoolOp):
            for value in node.values:
                found = self._section_of(value, marks)
                if found:
                    return found
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
                and node.func.id in ("enumerate", "list", "reversed", "sorted", "tuple"):
            return self._section_of(node.args[0], marks) if node.args else None
        return None

    def keys_by_section(self) -> tuple[dict[str, set[str]], int, int]:
        """Какие ключи читаются у какого раздела; сколько связано."""
        result: dict[str, set[str]] = {}
        linked = 0
        total = 0

        for name, func in self.functions.items():
            marks = self.local.get(name, {})
            for node in ast.walk(func):
                key = None
                holder = None
                if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Constant) \
                        and isinstance(node.slice.value, str):
                    key, holder = node.slice.value, node.value
                elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                        and node.func.attr == "get" and node.args \
                        and isinstance(node.args[0], ast.Constant) \
                        and isinstance(node.args[0].value, str):
                    key, holder = node.args[0].value, node.func.value
                if key is None:
                    continue
                total += 1
                section = self._section_of(holder, marks)
                if section:
                    result.setdefault(section, set()).add(key)
                    linked += 1
        return result, linked, total

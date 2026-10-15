"""Кнопки, поля ввода и окошки. Обычные виджеты для pygame.

Здесь только отрисовка и обработка мыши/клавиатуры.
"""
from __future__ import annotations

import pygame

from config import (
    COL_ACCENT,
    COL_DIM,
    COL_LINE,
    COL_PANEL,
    COL_PANEL_2,
    COL_TEXT,
    COL_WARN,
)

_FONT_CACHE: dict[tuple[int, bool], pygame.font.Font] = {}
_PREFERRED = ["dejavusans", "freesans", "liberationsans", "arial", "notosans"]


def font(size: int, bold: bool = False) -> pygame.font.Font:
    key = (size, bold)
    if key in _FONT_CACHE:
        return _FONT_CACHE[key]
    path = None
    for name in _PREFERRED:
        path = pygame.font.match_font(name, bold=bold)
        if path:
            break
    f = pygame.font.Font(path, size) if path else pygame.font.Font(None, size)
    f.set_bold(bold and path is None)
    _FONT_CACHE[key] = f
    return f


def text(surface, value, pos, size=16, color=COL_TEXT, bold=False, center=False):
    img = font(size, bold).render(str(value), True, color)
    rect = img.get_rect()
    if center:
        rect.center = pos
    else:
        rect.topleft = pos
    surface.blit(img, rect)
    return rect


def clip_text(value: str, limit: int) -> str:
    value = str(value)
    return value if len(value) <= limit else value[: limit - 1] + "…"


def panel(surface, rect, color=COL_PANEL, border=COL_LINE, radius=8):
    pygame.draw.rect(surface, color, rect, border_radius=radius)
    if border:
        pygame.draw.rect(surface, border, rect, width=1, border_radius=radius)


class Button:
    def __init__(self, rect, label, action=None, hotkey=None, tone="normal"):
        self.rect = pygame.Rect(rect)
        self.label = label
        self.action = action
        self.hotkey = hotkey
        self.tone = tone
        self.enabled = True
        self.hover = False

    def draw(self, surface):
        if not self.enabled:
            bg, fg = (38, 40, 48), (100, 106, 120)
        elif self.tone == "accent":
            bg = (86, 70, 36) if not self.hover else (110, 90, 44)
            fg = COL_ACCENT
        elif self.tone == "danger":
            bg = (78, 40, 36) if not self.hover else (100, 52, 46)
            fg = COL_WARN
        else:
            bg = COL_PANEL_2 if not self.hover else (56, 62, 78)
            fg = COL_TEXT
        panel(surface, self.rect, bg, COL_LINE, radius=6)
        label = self.label
        if self.hotkey:
            label = f"{self.hotkey}  {label}"
        text(surface, clip_text(label, 26), self.rect.center, 15, fg, center=True)

    def handle(self, event) -> bool:
        if event.type == pygame.MOUSEMOTION:
            self.hover = self.rect.collidepoint(event.pos)
        elif (
            event.type == pygame.MOUSEBUTTONDOWN
            and event.button == 1
            and self.enabled
            and self.rect.collidepoint(event.pos)
        ):
            if self.action:
                self.action()
            return True
        return False


class TextInput:
    def __init__(self, rect, placeholder="", password=False, limit=40):
        self.rect = pygame.Rect(rect)
        self.value = ""
        self.placeholder = placeholder
        self.password = password
        self.limit = limit
        self.focused = False

    def draw(self, surface):
        border = COL_ACCENT if self.focused else COL_LINE
        panel(surface, self.rect, (28, 30, 38), border, radius=6)
        shown = "•" * len(self.value) if self.password else self.value
        if not shown:
            text(surface, self.placeholder, (self.rect.x + 10, self.rect.y + 9), 16, COL_DIM)
        else:
            if self.focused and pygame.time.get_ticks() // 500 % 2 == 0:
                shown += "|"
            text(surface, shown, (self.rect.x + 10, self.rect.y + 9), 16)

    def handle(self, event):
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            self.focused = self.rect.collidepoint(event.pos)
        elif event.type == pygame.KEYDOWN and self.focused:
            if event.key == pygame.K_BACKSPACE:
                self.value = self.value[:-1]
            elif event.key in (pygame.K_RETURN, pygame.K_KP_ENTER, pygame.K_TAB):
                return "submit"
            elif event.unicode and event.unicode.isprintable():
                if len(self.value) < self.limit:
                    self.value += event.unicode
        return None


class ListDialog:
    """Окно со списком. Что выбрали — уходит в on_pick."""

    ROW_H = 34

    def __init__(self, title, items, on_pick, subtitle=None, screen_size=(1280, 760)):
        self.title = title
        self.subtitle = subtitle
        self.items = items          # [(подпись, значение, пояснение)]
        self.on_pick = on_pick
        self.offset = 0
        self.visible = 11
        w, h = 720, 520
        self.rect = pygame.Rect(0, 0, w, h)
        self.rect.center = (screen_size[0] // 2, screen_size[1] // 2)
        self.close_rect = pygame.Rect(self.rect.right - 40, self.rect.y + 12, 28, 28)
        self.done = False

    def _row_rect(self, index):
        return pygame.Rect(
            self.rect.x + 16,
            self.rect.y + 76 + index * self.ROW_H,
            self.rect.width - 32,
            self.ROW_H - 4,
        )

    def draw(self, surface):
        overlay = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 170))
        surface.blit(overlay, (0, 0))

        panel(surface, self.rect, COL_PANEL, COL_ACCENT, radius=10)
        text(surface, self.title, (self.rect.x + 18, self.rect.y + 16), 20, COL_ACCENT, bold=True)
        if self.subtitle:
            text(surface, self.subtitle, (self.rect.x + 18, self.rect.y + 46), 14, COL_DIM)

        panel(surface, self.close_rect, COL_PANEL_2, COL_LINE, radius=4)
        text(surface, "×", self.close_rect.center, 20, COL_DIM, center=True)

        mouse = pygame.mouse.get_pos()
        shown = self.items[self.offset : self.offset + self.visible]
        for i, (label, _value, hint) in enumerate(shown):
            row = self._row_rect(i)
            hovered = row.collidepoint(mouse)
            panel(surface, row, (52, 58, 72) if hovered else COL_PANEL_2, None, radius=5)
            text(surface, clip_text(label, 46), (row.x + 10, row.y + 7), 16)
            if hint:
                img = font(14).render(clip_text(hint, 30), True, COL_DIM)
                surface.blit(img, (row.right - img.get_width() - 10, row.y + 9))

        if not self.items:
            text(
                surface,
                "Список пуст",
                (self.rect.centerx, self.rect.y + 140),
                18,
                COL_DIM,
                center=True,
            )

        if len(self.items) > self.visible:
            text(
                surface,
                f"{self.offset + 1}–{min(self.offset + self.visible, len(self.items))}"
                f" из {len(self.items)}   (колесо мыши)",
                (self.rect.centerx, self.rect.bottom - 26),
                14,
                COL_DIM,
                center=True,
            )

    def handle(self, event):
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            self.done = True
        elif event.type == pygame.MOUSEWHEEL:
            limit = max(0, len(self.items) - self.visible)
            self.offset = max(0, min(limit, self.offset - event.y))
        elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.close_rect.collidepoint(event.pos):
                self.done = True
                return
            if not self.rect.collidepoint(event.pos):
                self.done = True
                return
            shown = self.items[self.offset : self.offset + self.visible]
            for i, item in enumerate(shown):
                if self._row_rect(i).collidepoint(event.pos):
                    self.done = True
                    self.on_pick(item[1])
                    return


class TextDialog:
    """Окно с текстом и прокруткой. Показываем в нём отчёты из базы."""

    def __init__(self, title, lines, screen_size=(1280, 760)):
        self.title = title
        self.lines = lines or ["(пусто)"]
        self.offset = 0
        self.visible = 22
        self.rect = pygame.Rect(0, 0, 860, 600)
        self.rect.center = (screen_size[0] // 2, screen_size[1] // 2)
        self.close_rect = pygame.Rect(self.rect.right - 40, self.rect.y + 12, 28, 28)
        self.done = False

    def draw(self, surface):
        overlay = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 175))
        surface.blit(overlay, (0, 0))

        panel(surface, self.rect, COL_PANEL, COL_ACCENT, radius=10)
        text(surface, self.title, (self.rect.x + 18, self.rect.y + 16), 20, COL_ACCENT, bold=True)
        panel(surface, self.close_rect, COL_PANEL_2, COL_LINE, radius=4)
        text(surface, "×", self.close_rect.center, 20, COL_DIM, center=True)

        mono = font(14)
        for i, line in enumerate(self.lines[self.offset : self.offset + self.visible]):
            img = mono.render(clip_text(line, 96), True, COL_TEXT)
            surface.blit(img, (self.rect.x + 18, self.rect.y + 56 + i * 23))

        text(
            surface,
            "колесо мыши — прокрутка, Esc — закрыть",
            (self.rect.centerx, self.rect.bottom - 24),
            14,
            COL_DIM,
            center=True,
        )

    def handle(self, event):
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            self.done = True
        elif event.type == pygame.MOUSEWHEEL:
            limit = max(0, len(self.lines) - self.visible)
            self.offset = max(0, min(limit, self.offset - event.y * 3))
        elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.close_rect.collidepoint(event.pos) or not self.rect.collidepoint(event.pos):
                self.done = True


class Toast:
    """Плашка внизу экрана, которая сама пропадает."""

    def __init__(self):
        self.message = ""
        self.until = 0
        self.tone = "info"

    def show(self, message, tone="info", seconds=4.0):
        self.message = message
        self.tone = tone
        self.until = pygame.time.get_ticks() + int(seconds * 1000)

    def draw(self, surface):
        if pygame.time.get_ticks() > self.until or not self.message:
            return
        colors = {"info": COL_TEXT, "ok": (106, 190, 140), "error": COL_WARN}
        width = min(900, 24 + font(16).size(self.message)[0])
        rect = pygame.Rect(0, 0, width, 40)
        rect.midbottom = (surface.get_width() // 2, surface.get_height() - 14)
        panel(surface, rect, (20, 22, 28), colors.get(self.tone, COL_LINE), radius=8)
        text(surface, self.message, rect.center, 16, colors.get(self.tone, COL_TEXT), center=True)

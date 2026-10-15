# -*- mode: python ; coding: utf-8 -*-
"""Сборка одного exe с игрой «Куратор музея».

Что важно знать про эту сборку:

  * SQL-скрипты установки схемы кладутся ВНУТРЬ exe (секция datas).
    При запуске PyInstaller распаковывает их во временную папку,
    а python/resources.py находит её через sys._MEIPASS.

  * Клиент Oracle не нужен: oracledb работает в тонком режиме, то есть
    говорит с сервером по сети сам, без Oracle Instant Client.
    Поэтому exe можно просто скопировать на учебный стенд.

  * Главная тонкость — hiddenimports. Часть oracledb скомпилирована из
    Cython (.pyx), и PyInstaller не может прочитать, что эти модули
    импортируют: анализатор умеет разбирать только обычный .py.
    Поэтому всё, что oracledb подтягивает изнутри, перечислено руками.
    Симптом пропущенного модуля — окно «No module named ...» при
    запуске готового exe.

  * console=False — окно консоли не мелькает. Если нужно увидеть
    traceback при отладке, поменяйте на True и пересоберите.

Сборка:  pyinstaller MuseumCurator.spec --noconfirm
"""
from PyInstaller.utils.hooks import collect_all, collect_submodules

block_cipher = None

# oracledb: забираем пакет целиком вместе с данными и бинарниками.
ora_datas, ora_binaries, ora_hidden = collect_all("oracledb")

# cryptography нужна тонкому режиму при согласовании соединения.
crypto_datas, crypto_binaries, crypto_hidden = collect_all("cryptography")

# Модули стандартной библиотеки, которые oracledb импортирует из
# скомпилированного кода. Список намеренно с запасом: лишний модуль
# добавляет килобайты, пропущенный — роняет exe при запуске.
STDLIB_FOR_ORACLEDB = [
    "getpass",
    "secrets",
    "ssl",
    "hashlib",
    "hmac",
    "base64",
    "binascii",
    "uuid",
    "decimal",
    "socket",
    "select",
    "datetime",
    "json",
    "array",
    "configparser",
    "platform",
    "unicodedata",
    "urllib.parse",
    "urllib.request",
    "xml.etree.ElementTree",
    "getopt",
]

a = Analysis(
    ["python/main.py"],
    pathex=["python"],
    binaries=ora_binaries + crypto_binaries,
    # Каждый скрипт установки попадает в подпапку sql внутри exe.
    datas=[
        ("sql/00_drop_all.sql", "sql"),
        ("sql/01_tables.sql", "sql"),
        ("sql/02_reference_data.sql", "sql"),
        ("sql/03_catalog_data.sql", "sql"),
        ("sql/04_package_spec.sql", "sql"),
        ("sql/05_package_body.sql", "sql"),
    ] + ora_datas + crypto_datas,
    hiddenimports=(
        ora_hidden
        + crypto_hidden
        + collect_submodules("oracledb")
        + STDLIB_FOR_ORACLEDB
    ),
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # Исключаем только то, что точно не нужно и заметно весит.
    # Раньше здесь были pydoc и doctest — их лучше не трогать,
    # на них завязаны неожиданные части стандартной библиотеки.
    excludes=["tkinter", "matplotlib", "numpy", "PIL", "pytest"],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="MuseumCurator",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

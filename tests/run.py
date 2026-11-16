"""Run addon Lua 5.1 syntax and mocked-client regression checks.

Install the optional development dependency with:
  python -m pip install --target .tools/runtime lupa
Then run: python tests/run.py
Nothing from .tools or tests belongs in the installed addon.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / ".tools" / "runtime"), str(ROOT / ".tools" / "python")]
try:
    from lupa.lua51 import LuaRuntime
except ImportError as exc:
    raise SystemExit("Lua 5.1 test runtime missing: install lupa in .tools/runtime") from exc

lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(source, name) local fn, err = loadstring(source, name); assert(fn, err); return fn end")
for manifest in sorted(ROOT.glob("*/*.toc")):
    if manifest.stem != manifest.parent.name:
        continue
    for path in sorted(manifest.parent.rglob("*.lua")):
        name = path.relative_to(ROOT).as_posix()
        compile_lua(path.read_text(encoding="utf-8-sig"), "@" + name)
        print("SYNTAX PASS", name, flush=True)

for path in sorted((ROOT / "tests").glob("*_test.lua")):
    print("RUN", path.name, flush=True)
    test_lua = LuaRuntime(unpack_returned_tuples=True)
    test_lua.globals().TEST_ROOT = ROOT.as_posix()
    test_lua.execute(path.read_text(encoding="utf-8-sig"), name="@tests/" + path.name)

print("All available addon checks passed.", flush=True)

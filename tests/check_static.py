"""Dependency-free static safety checks for Spatial Plates. Run: python3 tests/check_static.py"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LUA_FILES = [ROOT / name for name in ("Config.lua", "Presets.lua", "Appearance.lua", "Core.lua")]
source = "\n".join(path.read_text(encoding="utf-8") for path in LUA_FILES)

FORBIDDEN = re.compile(
    r"\b(?:UnitHealth(?:Max)?|UnitPower(?:Max)?|UnitAura|C_UnitAuras|"
    r"GetSpellCooldown|GetSpellCharges|CombatLogGetCurrentEventInfo|CombatLog|"
    r"UnitThreatSituation|UnitDetailedThreatSituation|UnitThreatPercentageOfLead|"
    r"UnitHealPrediction|UnitGetIncomingHeals|UnitGetTotalAbsorbs|UnitGetTotalHealAbsorbs|"
    r"hooksecurefunc|RegisterForClicks)\b",
    re.IGNORECASE,
)
violations = FORBIDDEN.findall(source)
if violations:
    print("FAIL forbidden combat or secure-hook API tokens:", sorted(set(violations)))
    sys.exit(1)

required_toc = (ROOT / "SpatialPlates.toc").read_text(encoding="utf-8")
required_lines = [
    "## Interface: 16001",
    "## Title: Spatial Plates",
    "## SavedVariables: SpatialPlatesDB",
    "Config.lua",
    "Presets.lua",
    "Appearance.lua",
    "Core.lua",
]
for line in required_lines:
    if line not in required_toc:
        print("FAIL TOC missing:", line)
        sys.exit(1)
if not (required_toc.index("Config.lua") < required_toc.index("Presets.lua") < required_toc.index("Appearance.lua") < required_toc.index("Core.lua")):
    print("FAIL TOC load order")
    sys.exit(1)

readme = (ROOT / "README.md").read_text(encoding="utf-8")
if "AddOns/SpatialPlates/SpatialPlates.toc" not in readme:
    print("FAIL installation instructions must use a SpatialPlates folder matching the TOC")
    sys.exit(1)

for token in ("issecretvalue", "UnitDistanceSquared", "C_Map.GetBestMapForUnit", "NAME_PLATE_UNIT_REMOVED"):
    if token not in source:
        print("FAIL missing defensive mechanism:", token)
        sys.exit(1)

print("PASS static safety scan: no forbidden API/hook tokens; TOC and key guards present")

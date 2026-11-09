import re
plan=open("docs/superpowers/plans/2026-10-12-stage-8.md",encoding="utf-8").read()
task=plan.split("### Task 3:")[1].split("### Task 4:")[0]
B=re.findall(r"```gdscript\n(.*?)```",task,re.S)
def edit(p,a,b):
    s=open(p,encoding="utf-8").read(); assert s.count(a)==1,(p,a[:60]); open(p,"w",encoding="utf-8",newline="\n").write(s.replace(a,b))
pg="scripts/playground.gd"; s=open(pg,encoding="utf-8").read()
# (a)
edit(pg,"var _show_zones := false\n","var _show_zones := false\n"+B[1])
# (b) replace apply_preset body
s=open(pg,encoding="utf-8").read()
start=s.index("func apply_preset(preset_name: String) -> void:")
end=s.index("\n\n\nfunc reset_scene()")
s=s[:start]+B[2].rstrip("\n")+s[end:]
open(pg,"w",encoding="utf-8",newline="\n").write(s)
# (c) after apply_preset
edit(pg,"\n\n\nfunc reset_scene()","\n\n\n"+B[3].rstrip("\n")+"\n\n\nfunc reset_scene()")
# (d)
edit(pg,"\tplayer.input_enabled = index != SCOUT\n",B[4])
# (e)
edit(pg,"\tif not (event is InputEventKey and event.pressed and not event.echo):\n\t\treturn\n",B[5]+"\t\treturn\n" if not B[5].rstrip().endswith("return") else B[5])
dp="scripts/ui/dev_panel.gd"
edit(dp,"var _status: Label\n","var _status: Label\n"+B[6])
s=open(dp,encoding="utf-8").read()
start=s.index('\t_section("Presets")'); end=s.index('\tgrid.add_child(_button("Reset", _pg.reset_scene))\n')+len('\tgrid.add_child(_button("Reset", _pg.reset_scene))\n')
s=s[:start]+B[7]+s[end:]; open(dp,"w",encoding="utf-8",newline="\n").write(s)
s=open(dp,encoding="utf-8").read()
i=s.index("func refresh_views() -> void:"); j=s.index("\n\n\nfunc _button(")
s=s[:j]+"\n\n\n"+B[8].rstrip("\n")+s[j:]; open(dp,"w",encoding="utf-8",newline="\n").write(s)
edit(dp,"## Controls never take keyboard focus, so WASD and hotkeys keep working.\n",B[9])
print("ok")

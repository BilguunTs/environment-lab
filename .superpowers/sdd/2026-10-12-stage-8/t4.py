import re
plan=open("docs/superpowers/plans/2026-10-12-stage-8.md",encoding="utf-8").read()
task=plan.split("### Task 4:")[1].split("### Task 5:")[0]
B=re.findall(r"```gdscript\n(.*?)```",task,re.S)
def edit(p,a,b):
    s=open(p,encoding="utf-8").read(); assert s.count(a)==1,(p,a[:70]); open(p,"w",encoding="utf-8",newline="\n").write(s.replace(a,b))
open("scripts/compare.gd","w",encoding="utf-8",newline="\n").write(B[1])
pg="scripts/playground.gd"
edit(pg,"var _typing := false  # a panel text field has focus: no hotkeys, no walking\n","var _typing := false  # a panel text field has focus: no hotkeys, no walking\n"+B[2])
edit(pg,"\t_build_hud()\n","\t_build_hud()\n"+B[3])
edit(pg,"\tplayer.input_enabled = not on and _view != SCOUT\n","\tplayer.input_enabled = not on and _view != SCOUT\n\n\n"+B[4].rstrip("\n")+"\n")
s=open(pg,encoding="utf-8").read()
i=s.index("func _unhandled_input(event: InputEvent) -> void:"); j=s.index("\n\n\n",i)
s=s[:i]+B[5].rstrip("\n")+s[j:]; open(pg,"w",encoding="utf-8",newline="\n").write(s)
edit(pg,"func _set_view(index: int) -> void:\n","func _set_view(index: int) -> void:\n"+B[6])
s=open(pg,encoding="utf-8").read()
i=s.index('\t_hud.text = "%s   %d°'); j=s.index("\n",i)
s=s[:i]+B[7].rstrip("\n")+s[j:]; open(pg,"w",encoding="utf-8",newline="\n").write(s)
dp="scripts/ui/dev_panel.gd"
edit(dp,"const ACCENT := Color(0.95, 0.68, 0.35)\n","const ACCENT := Color(0.95, 0.68, 0.35)\n"+B[8])
edit(dp,"var _preset_name: LineEdit\n","var _preset_name: LineEdit\n"+B[9])
edit(dp,'\t_section("Presets")\n',B[10]+'\n\t_section("Presets")\n')
s=open(dp,encoding="utf-8").read()
i=s.index("func notify(text: String) -> void:"); j=s.index("\n\n\n",i)
s=s[:j]+"\n\n\n"+B[11].rstrip("\n")+s[j:]; open(dp,"w",encoding="utf-8",newline="\n").write(s)
print("ok")

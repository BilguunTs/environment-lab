import re
plan=open("docs/superpowers/plans/2026-10-12-stage-8.md",encoding="utf-8").read()
task=plan.split("### Task 5:")[1].split("### Task 6:")[0]
B=re.findall(r"```gdscript\n(.*?)```",task,re.S)
def edit(p,a,b):
    s=open(p,encoding="utf-8").read(); assert s.count(a)==1,(p,a[:70]); open(p,"w",encoding="utf-8",newline="\n").write(s.replace(a,b))
pg="scripts/playground.gd"
edit(pg,"var compare: Compare\n","var compare: Compare\n"+B[1])
edit(pg,"\t_build_hud()\n","\t_build_hud()\n"+B[2])
edit(pg,"\tcompare.changed.connect(_on_compare_changed)\n","\tcompare.changed.connect(_on_compare_changed)\n"+B[3])
s=open(pg,encoding="utf-8").read()
i=s.index("## Saves the current frame without the panel/HUD"); j=s.index("\n\n\n## Renders every fixed view",i)
s=s[:i]+B[4].rstrip("\n")+s[j:]; open(pg,"w",encoding="utf-8",newline="\n").write(s)
edit(pg,"\t\tKEY_P:\n\t\t\tcompare.pin()\n","\t\tKEY_P:\n\t\t\tcompare.pin()\n"+B[5])
s=open(pg,encoding="utf-8").read()
i=s.index("func set_param(key: String, value: Variant) -> void:"); j=s.index("\n\n\nfunc get_state()",i)
s=s[:j]+"\n"+B[6].rstrip("\n")+s[j:]; open(pg,"w",encoding="utf-8",newline="\n").write(s)
cp="scripts/compare.gd"
edit(cp,'const EXCLUDE := ["view", "guides_grid", "guides_center", "guides_aspect", "value_mode", "value_squint", "value_split"]\n',
 'const EXCLUDE := ["view", "guides_grid", "guides_center", "guides_aspect", "value_mode", "value_squint", "value_split"]\n'+B[7])
edit(cp,"var _b_state := {}  # the live state while A is shown\n","var _b_state := {}  # the live state while A is shown\n"+B[8])
edit(cp,"func show_a(on: bool) -> void:\n","func show_a(on: bool) -> void:\n"+B[9])
s=open(cp,encoding="utf-8").read()
i=s.index("## Back to plain B, e.g. before Scout takes over the camera."); j=s.index("\n\n\n",i)
s=s[:i]+B[10].rstrip("\n")+s[j:]; open(cp,"w",encoding="utf-8",newline="\n").write(s)
impl=B[11].replace("a_image = await render_state(a_state)","a_image = await render_state(_a_here())")
assert "render_state(_a_here())" in impl
open(cp,"a",encoding="utf-8",newline="\n").write("\n\n"+impl)
edit(cp,'''	return "SHOWING A" if showing_a else "B · A pinned"''','''	if showing_a:
		return "SHOWING A"  # X held: the split overlay steps aside, so say what's on screen
	if split:
		return "SPLIT  A | B"
	return "B · A pinned"''')
edit(cp,"## P pins A, hold X to see A. Talks to","## P pins A, hold X to see A, Z splits the screen (frozen A image | live B). Talks to")
open("scripts/ui/compare_view.gd","w",encoding="utf-8",newline="\n").write(B[14])
dp="scripts/ui/dev_panel.gd"
edit(dp,'\tcompare_row.add_child(_button("Pin A (P)", _pg.compare.pin))\n','\tcompare_row.add_child(_button("Pin A (P)", _pg.compare.pin))\n'+B[15])
s=open(dp,encoding="utf-8").read()
i=s.index('\t_note("Pin A, change something, then hold X to see A. A and B share'); j=s.index("\n",i)
s=s[:i]+B[16].rstrip("\n")+s[j:]; open(dp,"w",encoding="utf-8",newline="\n").write(s)
print("ok")

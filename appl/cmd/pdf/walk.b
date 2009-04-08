implement PdfWalk;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
	draw: Draw;
	Display, Image: import draw;
include "string.m";
	str: String;
include "arg.m";
include "tk.m";
	tk: Tk;
include	"tkclient.m";
	tkclient: Tkclient;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "filter.m";
include "pdfread.m";
	pdfread: Pdfread;
	Single, Many, Doc, Obj, Str, Input: import pdfread;

PdfWalk: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};


Hist: adt {
	a:	array of (string, ref Obj.Objref);

	mk:	fn(): ref Hist;
	clone:	fn(h: self ref Hist): ref Hist;
	add:	fn(h: self ref Hist, p: string, o: ref Obj.Objref);
	settext:	fn(h: self ref Hist, tw: string, perm: int);
	resettext:	fn(h: self ref Hist, tw: string, perm: int);
};

Histmem: adt {
	a:	array of ref Hist;

	mk:	fn(): ref Histmem;
	add:	fn(m: self ref Histmem, h: ref Hist);
};


doc: ref Doc;
dflag: int;
file: string;
t: ref Tk->Toplevel;
wmctl: chan of string;

hist: ref Hist;
histmem: ref Histmem;

tkcmds := array[] of {
	"frame .fhist",
	"frame .f",
	"frame .ptext",
	"frame .ctext",
	"frame .stext",

	"text .hist -height 6h -yscrollcommand {.histscroll set}",
	"scrollbar .histscroll -command {.hist yview}",
	"pack .histscroll -side left -fill y -in .fhist",
	"pack .hist -side right -in .fhist -expand 1 -fill x",

	"text .path -height 1h",
	"pack .path -in .ptext -expand 1 -fill x",

	"button .up -text Up -command {send cmd up}",
	"button .remem -text Remember -command {send cmd remember}",
	"button .index -text Index -command {send cmd index}",
	"label .findl -text Name:",
	"entry .e",
	"bind .e <Key-\n> {send cmd find}",
	"button .find -text Find -command {send cmd find}",
	"pack .up .remem .index .findl .e .find -side left -in .f -expand 1 -fill x",

	"text .c -yscrollcommand {.cscroll set}",
	"scrollbar .cscroll -command {.c yview}",
	"pack .cscroll -side left -fill y -in .ctext",
	"pack .c -side right -in .ctext -expand 1 -fill both",

	"text .s -yscrollcommand {.sscroll set}",
	"scrollbar .sscroll -command {.s yview}",
	"pack .sscroll -side left -fill y -in .stext",
	"pack .s -side right -in .stext -expand 1 -fill both",
	".s tag configure operator -foreground red",
	".s tag configure indent -foreground blue",

	"pack .stext -side bottom -fill both -expand 1",
	"pack .ctext -side bottom -fill both -expand 1",
	"pack .fhist -fill x",
	"pack .f -fill x",
	"pack .ptext -fill x",
	"pack propagate . 0",
	". configure -width 800 -height 600",
	"update",
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys  = load Sys  Sys->PATH;
	if(ctxt == nil)
		fail("no window context");
	draw = load Draw Draw->PATH;
	str = load String String->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;
	arg := load Arg Arg->PATH;
	pdfread = load Pdfread Pdfread->PATH;
	pdfread->init();

	arg->init(args);
	arg->setusage(arg->progname()+" [-d] file");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	file = hd args;

	err: string;
	(doc, err) = Doc.open(file);
	if(err != nil)
		fail(err);

	tkclient->init();
	(t, wmctl) = tkclient->toplevel(ctxt, "", "pdf/walk", Tkclient->Appl);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for (i := 0; i < len tkcmds; i++)
		tk->cmd(t,tkcmds[i]);

	setobj(doc.trailer);
	hist = Hist.mk();
	hist.resettext(".path", 0);
	histmem = Histmem.mk();

	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or s = <-t.wreq =>
		tkclient->wmctl(t, s);
	menu := <-wmctl =>
		case menu {
		"exit" =>
			return;
		* =>
			tkclient->wmctl(t, menu);
		}
	bcmd := <-cmd =>
		(l, r) := str->splitstrl(bcmd, " ");
		if(r != nil)
			r = r[1:];
		if(l == "up")
			(l, r) = ("hist", "-1 "+string (len hist.a-2));

		case l {
		* =>
			sys->print("%s\n", bcmd);
		"index" or "find" =>
			# read through pdf file, reading all objects (but do not start filters i suppose)
			# keep a table mapping:  key => list of (value => objref)
			# only for predefined keys
			# when searching, fill content text field with results, simply all objects that match
			tk->cmd(t, ".c delete 0.0 end; .s delete 0.0 end; .c insert end {indexing and searching not yet implemented}; update");
			;
		"remember" =>
			histmem.add(hist.clone());
			hist.settext(".hist", 1);
			tk->cmd(t, ".hist see end; update");
		"hist" =>
			#print("have hist %q\n", bcmd);
			mems: string;
			(mems, r) = str->splitstrl(r, " ");
			memid := int mems;
			if(memid >= 0)
				hist = histmem.a[memid].clone();
			id := int r[1:];
			if(id >= len hist.a) {
				sys->print("bad history ref");
				continue;
			}

			if(id < 0) {
				hist.a = hist.a[:0];
				setobj(doc.trailer);
			} else {
				if(id+1 < len hist.a)
					hist.a = hist.a[:id+1];
				(nil, oref) := hist.a[id];
				(obj, oerr) := doc.deref(oref);
				if(oerr != nil)
					cseterror(sprint("reading object reference (%s): %s", oref.text(), oerr));
				setobj(obj);
			}
			hist.resettext(".path", 0);
		"objref" =>
			#sys->print("have %s, q=%q\n", l, r);
			ids, gens, newpath: string;
			(ids, r) = str->splitstrl(r, " ");
			(gens, r) = str->splitstrl(r[1:], " ");
			newpath = r[1:];
			id := int ids;
			gen := int gens;
			oref := ref Obj.Objref(id, gen);

			(obj, oerr) := doc.deref(oref);
			if(oerr != nil) {
				cseterror(sprint("reading object reference (%s): %s", oref.text(), oerr));
				continue;
			}
			setobj(obj);
			hist.add(newpath, oref);
			hist.resettext(".path", 0);
		}
	}
}

cseterror(s: string)
{
	tk->cmd(t, ".c delete 0.0 end; .c insert end '"+s);
	tk->cmd(t, ".c update");
}

cadd(s: string)
{
	tk->cmd(t, ".c insert end '"+s);
}

tag := 0;

caddtag(ks: string, v: ref Obj.Objref, path: string)
{
	ts := "t"+string tag++;
#sys->print("adding tag, ks=%s ts=%s path=%s\n", ks, ts, path);
	tk->cmd(t, sprint(".c tag add %s {end -%dc} {end -1c}", ts, 1+len ks));
	tk->cmd(t, sprint(".c tag bind %s <ButtonRelease-1> {send cmd objref %d %d %s}", ts, v.id, v.gen, path));
}

setobjtext(oo: ref Obj, indent: int, path: string)
{
	l := sprint("%*s", indent, "");
	s := "";
	pick o := oo {
	Boolean =>	s = l+"bool:"+string o.v;
	Numeric =>	s = l+"num:"+o.orig;
	Name =>		s = l+"name:"+o.s.text();
	String =>	s = l+"string:"+o.s.text();
	Dict =>		cadd(l+"dict:[\n");
			for(i := 0; i < len o.d; i++) {
				(k, v) := o.d[i];
				ks := l+k.text()+":";
				cadd(ks);
				pick ov := v {
				Objref =>
					caddtag(ks, ov, path+".*"+k.text());
				}
				cadd("\t");
				setobjtext(v, indent+1, path+"."+k.text());
				cadd("\n");
			}
			cadd(l+"]");
			return;
	Array =>	cadd(l+"array:[\n");
			for(i := 0; i < len o.a; i++) {
				ks := l+string i+":";
				cadd(ks);
				pick ov := o.a[i] {
				Objref =>
					caddtag(ks, ov, path+".*"+string i);
				}
				cadd("\t");
				setobjtext(o.a[i], indent+1, path+"."+string i);
				cadd("\n");
			}
			cadd(l+"]");
			return;
	Objref =>	os := (l+"objref:"+string o.id+","+string o.gen);
			cadd(os);
			caddtag(os, o, path);
	Operator =>	s = l+"op:"+o.s;
	Null =>		s = l+"null:";
	Stream =>	s = l+"stream:(\n"+o.d.text()+",\n"+o.s.text()+"\n)";
			setstream(o);
	* =>		raise "missing case for pick obj";
	}
	cadd(s);
}

setstream(so: ref Obj.Stream)
{
	tk->cmd(t, ".s delete 0.0 end");
	s := "";
	indent := "";
	for(;;) {
		(obj, err) := pdfread->readtype(so.s, 1);
		if(err != "") {
			tk->cmd(t, ".s delete 0.0 end; .s insert end 'error reading stream: "+err);
			so.s.rewind();
			return;
		}
		if(obj == nil)
			return;
		pick o := obj {
		* =>
			s += " "+o.packtext();
		Operator =>
			newindent := indent;
			which := "indent";
			case o.s {
			"ET" or "EX" =>
				if(len indent >= 4)
					indent = indent[:len indent-4];
				newindent = indent;
			"BT" or "BX" =>
				newindent += "    ";
			* =>
				which = "operator";
			}
			s += " "+o.packtext()+"\n";
			s = indent+s[1:];
			tk->cmd(t, ".s insert end '"+s);
			tk->cmd(t, sprint(".s tag add %s {end -%dc} {end -1c}", which, 2+len o.packtext()));
			s = "";
			indent = newindent;
		}
	}
#print("done setting stream contents");
	tk->cmd(t, ".s see 1.0; update");
}


setobj(o: ref Obj)
{
	tk->cmd(t, ".c delete 0.0 end");
	tk->cmd(t, ".s delete 0.0 end");
	for(i := 0; i < tag; i++)
		tk->cmd(t, sprint(".c tag delete t%d", i));
	tag = 0;
	setobjtext(o, 0, "");
	tk->cmd(t, "update");
}


Hist.mk(): ref Hist
{
	return ref Hist(array[0] of (string, ref Obj.Objref));
}

Hist.add(h: self ref Hist, p: string, o: ref Obj.Objref)
{
	na := array[len h.a+1] of (string, ref Obj.Objref);
	#test := array[len h.a+1] of ref (string, ref Obj.Objref);
	#test[0] = ref ("", nil);
	na[:] = h.a;
	na[len h.a] = (p, o);
	h.a = na;
}

Hist.resettext(h: self ref Hist, tw: string, perm: int)
{
	tk->cmd(t, tw+" delete 0.0 end");
	for(i := 0; i <= len h.a; i++)
		tk->cmd(t, tw+" tag delete h"+string i);
	h.settext(tw, perm);
}

ptag := 0;

Hist.settext(h: self ref Hist, tw: string, perm: int)
{
	os := "Trailer";
	lpath := os;
	tk->cmd(t, tw+" insert end '"+os);
	tk->cmd(t, sprint("%s tag add h0 {end -%dc} {end -1c}", tw, 1+len os));
	tk->cmd(t, sprint("%s tag bind h0 <ButtonRelease-1> {send cmd hist -1 -1}", tw));
	for(i := 0; i < len h.a; i++) {
		(s, nil) := h.a[i];
		lpath += s;
		ts := "h"+string (i+1);
		if(perm)
			ts = "p"+string ptag++;
		tk->cmd(t, tw+" insert end '"+s);
		tk->cmd(t, sprint("%s tag add %s {end -%dc} {end -1c}", tw, ts, 1+len s));
		memid := -1;
		if(perm)
			memid = len histmem.a-1;
		tk->cmd(t, sprint("%s tag bind %s <ButtonRelease-1> {send cmd hist %d %d}", tw, ts, memid, i));
	}
	if(perm)
		tk->cmd(t, tw+" insert end '\n");
	tk->cmd(t, "update");
}

Hist.clone(h: self ref Hist): ref Hist
{
	a := array[len h.a] of (string, ref Obj.Objref);
	a[:] = h.a;
	return ref Hist(a);
}

Histmem.mk(): ref Histmem
{
	return ref Histmem(array[0] of ref Hist);
}

Histmem.add(m: self ref Histmem, h: ref Hist)
{
	na := array[len m.a+1] of ref Hist;
	na[:] = m.a;
	na[len m.a] = h;
	m.a = na;
}

fail(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	raise "fail:"+s;
}

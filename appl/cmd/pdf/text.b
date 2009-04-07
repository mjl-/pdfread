implement PdfText;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "filter.m";
include "pdfread.m";
	pdfread: Pdfread;
	Single, Many, Doc, Obj, Str: import pdfread;

PdfText: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};


doc: ref Doc;
tflag, dflag: int;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	pdfread = load Pdfread Pdfread->PATH;
	pdfread->init();

	arg->init(args);
	arg->setusage(arg->progname()+" [-td] file");
	while((c := arg->opt()) != 0)
		case c {
		't' =>	tflag++;
		'd' =>	dflag++;
			pdfread->dflag = dflag;
		* =>	arg->usage();
		}

	args = arg->argv();
	if(len args != 1)
		arg->usage();

	f := hd args;
	err: string;
	(doc, err) = Doc.open(f);
	if(err != nil)
		fail(err);
	if(!tflag)
		sys->print("version=%s xref=%d nobjs=%d\n", doc.version, doc.xref, len doc.objs);
	for(i := 0; i < len doc.objs; i++) {
		(offset, id, gen, mode) := doc.objs[i];
		if(!tflag && dflag)
			sys->print("%10bd %5d %5d %1d\n", offset, id, gen, mode);
	}
	if(!tflag)
		sys->print("trailer=%q\n", doc.trailer.text());

	root := xrefer(doc.trailer, "Root");
	if(!tflag)
		sys->print("root: %q\n", root.text());
	handle(root);
}

stack: list of ref Obj;
needstack(n: int, s: string)
{
	if(len stack != n)
		fail(sprint("bad stack, need %d obj for %s, have %d", n, s, len stack));
}

popobj(): ref Obj
{
	if(len stack == 0)
		fail("pop on empty stack");
	o := hd stack;
	stack = tl stack;
	return o;
}

popnum(): real
{
	pick o := oo := popobj() {
	Numeric =>	return o.v;
	}
	fail("bad type, need number/real, have "+oo.text());
	return 0.0;
}

popstring(): string
{
	pick o := oo := popobj() {
	String =>	return o.s.text();
	}
	fail("bad type, need string, have "+oo.text());
	return nil;
}

poparray(): array of ref Obj
{
	pick o := oo := popobj() {
	Array =>	return o.a;
	}
	fail("bad type, need string, have "+oo.text());
	return nil;
}

handle(obj: ref Obj)
{
	(p, err) := obj.getname("Type", Single);
	if(err != nil)
		fail("missing key 'Type': "+err);
	case s := string p[0].s.a {
	"Catalog" =>
		pages := xrefer(obj, "Pages");
		if(!tflag)
			sys->print("pages: %q\n", pages.text());
		handle(pages);

	"Pages" =>
		kids := xreferarray(obj, "Kids", 1);
		for(j := 0; j < len kids; j++)
			if(!tflag)
				sys->print("kids[%d]: %q\n", j, kids[j].text());
		for(j = 0; j < len kids; j++)
			handle(kids[j]);

	"Page" =>
		resources := xrefer(obj, "Resources");
		if(!tflag)
			sys->print("resources: %s\n", resources.text());
		contentarr := xreferarray(obj, "Contents", 0);
		if(len contentarr == 1) {
			pick a := contentarr[0] {
			Array =>
				na := array[len a.a] of ref Obj;
				for(j := 0; j < len a.a; j++) {
					pick blahobj := a.a[j] {
					Objref =>
						(no, blaherr) := doc.deref(blahobj);
						if(blaherr != nil)
							fail("derefing array: "+blaherr);
						na[j] = no;
					* =>	fail("bad type in contents array, need objref");
					}
				}
				contentarr = na;
			}
		}
		text := "";
		intext := 0;
		havestr := 0;
		xscale := yscale := fontsize := 1.0;
		for(k := 0; k < len contentarr; k++) {
			stream: ref Obj.Stream;
			pick cont := contentarr[k] {
			* =>	fail(sprint("contents not a stream: %q", cont.text()));
			Stream =>
				stream = cont;
			}
			for(;;) {
				(t, terr) := pdfread->readtype(stream.s, 1);
				if(terr != nil)
					fail(sprint("parsing contents: %s (%s)", terr, stream.text()));
				if(t == nil)
					break;
				pick o := t {
				Operator =>
					if(o.s != "ET" && o.s != "BT" && !intext)
						continue;
					case o.s {
					"ET" =>
						if(intext)
							intext = 0;
						else
							fail("ET outside text context");
						stack = nil;
					"BT" =>
						if(intext)
							fail("BT inside text context");
						intext = 1;
						stack = nil;
					"TJ" =>
						needstack(1, o.s);
						a := poparray();
						for(i := 0; i < len a; i++)
							pick arrobj := a[i] {
							String =>
								text += arrobj.s.text();
							Numeric =>
								spaces := int ((xscale*fontsize*-arrobj.v)/3500.0);
								while(spaces-- > 0)
									text += " ";
							* =>	fail("bad type in TJ array");
							}
						havestr = 1;
					"Tj" =>
						needstack(1, o.s);
						text += popstring();
						havestr = 1;
					"T*" =>
						needstack(0, o.s);
						text += "\n";
					"Td" or "TD" =>
						needstack(2, o.s);
						v := popnum();
						h := popnum();
						if(v != 0.0) text += "\n";
						if(h != 0.0) text += " ";
					"'" =>
						needstack(1, o.s);
						text += "\n"+popstring();;
						havestr = 1;
					"\"" =>
						needstack(3, o.s);
						text += "\n"+popstring();
						popnum();
						popnum();
						havestr = 1;
					"Tf" =>
						fontsize = popnum();
						popobj();
					"Tm" =>
						popnum();
						popnum();
						yscale = popnum();
						popnum();
						popnum();
						xscale = popnum();
					* =>
						say(sprint("unknown operator: %q", o.s));
						stack = nil;
					}
				* =>	stack = o::stack;
					if(dflag) say(sprint("put on stack: %q", o.text()));
				}
			}
		}

		if(intext)
			fail("contents: premature eof, still in text context");
		if(text != "")
			sys->print("%s\n", text);

	* =>
		fail("unknown type: "+s);
	}
}

refer(o: ref Obj, s: string): (ref Obj, string)
{
	(newo, err) := o.find(s);
	if(err != nil)
		return (nil, sprint("elem %#q: %s", s, err));

	pick oo := newo {
	Objref =>
		(obj, oerr) := doc.deref(oo);
		if(oerr!= nil)
			return (nil, sprint("reading %#q (%d,%d): %s", s, oo.id, oo.gen, oerr));
		return (obj, nil);
	* =>
		return (oo, nil);
	}
}

xrefer(o: ref Obj, s: string): ref Obj
{
	(obj, err) := refer(o, s);
	if(err != nil)
		fail(err);
	return obj;
}

xreferarray(oo: ref Obj, s: string, must: int): array of ref Obj
{
	(obj, err) := oo.find(s);
	if(err != nil)
		fail(sprint("elem %#q: %s", s, err));
	pick o := obj {
	Array =>
		a := array[0] of ref Obj;
		for(i := 0; i < len o.a; i++) {
			pick objref := o.a[i] {
			Objref =>
				(dstobj, oerr) := doc.deref(objref);
				if(oerr != nil)
					fail(sprint("elem in %#q: %s", s, oerr));
				na := array[len a+1] of ref Obj;
				na[:] = a;
				na[len a] = dstobj;
				a = na;
			* =>
				fail(sprint("elem in %#q: not a reference", s));
			}
		}
		return a;
	Objref =>
		if(must)
			fail(sprint("elem in %#q not array but objref", s));
		(dstobj, oerr) := doc.deref(o);
		if(oerr != nil)
			fail(sprint("elem in %#q: %s", s, oerr));
		return array[1] of {dstobj};
	}
	fail(sprint("elem %#q: not an array", s));
	return nil;
}

fail(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	raise "fail:"+s;
}

say(s: string)
{
	if(dflag)
		sys->fprint(sys->fildes(2), "%s\n", s);
}

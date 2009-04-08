implement PdfInflate;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "string.m";
	str: String;
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "lists.m";
	lists: Lists;
include "filter.m";
include "pdfread.m";
	pdfread: Pdfread;
	Doc, Obj, Objloc, Str, Input: import pdfread;

dflag: int;
b: ref Iobuf;
boff := big 0;

PdfInflate: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys  = load Sys  Sys->PATH;
	str = load String String->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	lists = load Lists Lists->PATH;
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
	file := hd args;

	b = bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	if(b == nil)
		fail(sprint("fopen: %r"));

	(doc, err) := Doc.open(file);
	if(err != nil)
		fail(err);

	puts(doc.version+"\n");
	obj: ref Obj;
	wobj := list of {ref Objloc(big 0, 0, 65535, 0)};
	for(i := 0; i < len doc.objs; i++) {
		loc := ref doc.objs[i];
		if(!loc.inuse)
			continue;
		(obj, err) = doc.readobj(loc);
		if(err != nil)
			fail(sprint("reading objloc %s: %s", objloctext(loc), err));
		wobj = ref Objloc (boff, loc.id, loc.gen, loc.inuse)::wobj;
		puts(sprint("%d %d obj\n", loc.id, loc.gen));
		pick o := obj {
		* =>
			puts(obj.pack());
			puts("\n");
		Stream =>
			buf := o.s.readall();
			if(buf == nil)
				fail(sprint("reading stream: %r"));

			# xxx could use heuristics to see if contents are drawing ops, and reformat them.
			length: ref Obj;
			length = ref Obj.Numeric (real len buf, string len buf);
			dict := ref Obj.Dict(array[] of {
				(Str(array of byte "Length"), length),
			});
			puts(dict.pack());
			puts("\nstream\n");
			putbuf(buf);
			puts("\nendstream\n");
		}
		puts("endobj\n");
	}

	wobja := l2a(wobj);
	sort(wobja, locidge);

	startxref := boff;
	b.puts("xref\n");
	nobj := 1;
	if(len wobja > 0)
		nobj = wobja[len wobja-1].id+1;
	b.puts(sprint("%d %d\n", 0, nobj));
	
	previd := 0;
	for(i = 0; i < len wobja; i++) {
		o := wobja[i];
		while(previd < o.id-1) {
			b.puts(sprint("%010d %05d f\n", 0, 65535));
			previd++;
		}
		ch := 'n';
		if(!o.inuse)
			ch = 'f';
		b.puts(sprint("%010bd %05d %c\n", o.offset, o.gen, ch));
		previd = o.id;
	}

	b.puts("trailer\n");
	trailer := doc.trailer;
	prevstr := Str(array of byte "Prev");  #other capitalization too?
	for(i = 0; i < len trailer.d; i++)
		if(trailer.d[i].t0.eq(prevstr)) {
			trailer.d[i:] = trailer.d[i+1:];
			trailer.d = trailer.d[:len trailer.d-1];
			break;
		}
	b.puts(doc.trailer.pack()+"\n");

	b.puts(sprint("startxref\n%bd\n", startxref));
	b.puts("%%EOF\n");

	b.flush();
}

puts(s: string)
{
	putbuf(array of byte s);
}

putbuf(d: array of byte)
{
	boff += big len d;
	if(b.write(d, len d) != len d)
		fail(sprint("write: %r"));
}

objloctext(l: ref Objloc): string
{
	return sprint("offset=%bd,id=%d,gen=%d,inuse=%d\n", l.offset, l.id, l.gen, l.inuse);
}

locidge(a, b: ref Objloc): int
{
	return a.id >= b.id;
}

sort[T](a: array of T, ge: ref fn(a, b: T): int)
{
	for(i := 1; i < len a; i++) {
		tmp := a[i];
		for(j := i; j > 0 && ge(a[j-1], tmp); j--)
			a[j] = a[j-1];
		a[j] = tmp;
	}
}

l2a[T](l: list of T): array of T
{
	a := array[len l] of T;
	i := 0;
	for(; l != nil; l = tl l)
		a[i++] = hd l;
	return a;
}

fail(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	raise "fail:"+s;
}

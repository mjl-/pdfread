implement Pdfread;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "string.m";
	str: String;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
	EOF, ERROR: import bufio;
include "filter.m";
	cascadefilter: Filter;
include "pdfread.m";


dflag = 0;

init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	bufio = load Bufio Bufio->PATH;
	cascadefilter = load Filter "/dis/lib/cascadefilter.dis";
	cascadefilter->init();
}

Doc.open(path: string): (ref Doc, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return (nil, sprint("opening %s: %r", path));
	b := bufio->open(path, Bufio->OREAD);
	if(b == nil)
		return (nil, sprint("opening %s: %r", path));
	in := ref Input.File(b);

	version := getline(in);
	if(!str->prefix("%PDF-1.", version))
		return (nil, sprint("unknown version/file type (%s)", version));

	ntry := 128;
	b.seek(big -ntry, Bufio->SEEKEND);
	n := b.read(buf := array[ntry] of byte, len buf);
	if(n < 0)
		return (nil, sprint("finding object table: %r"));
	buf = buf[:n];
	i := len buf-1;
	nl := 0;
	for(;;) {
		if(i < 0)
			return (nil, sprint("cannot find 'startxref'"));
		if(buf[i] == byte '\n')
			nl++;
	 	if(buf[i] == byte '\r' && (i == len buf-1 || buf[i+1] != byte '\n'))
			nl++;
		if(nl == 4) {
			i++;
			break;
		}
		i--;
	}
	b.seek(big -(len buf-i), Bufio->SEEKEND);
#sys->print("offset=%bd\n", b.offset());

	s := getline(in);
	if(s != "startxref")
		return (nil, sprint("bad value (%q), 'startxref' expected", s));
	s = getline(in);
	xref := int s;
	s = getline(in);
	if(s != "%%EOF")
		return (nil, sprint("bad value (%q), '%%EOF' expected", s));

	(objs, trailobj, err) := readtrailer(in, xref, array[0] of Objloc);
	if(err != nil)
		return (nil, "reading xref tables: "+err);

	return (ref Doc(fd, b, in, version, xref, trailobj, objs), nil);
}

isnewobj(a: array of Objloc, o: Objloc): int
{
	for(i := 0; i < len a; i++)
		if(a[i].id == o.id && a[i].gen == o.gen)
			return 0;
	return 1;
}

readtrailer(in: ref Input, xref: int, objs: array of Objloc): (array of Objloc, ref Obj.Dict, string)
{
say(sprint("reading trailer at xref=%d", xref));
	in.seek(big xref, Bufio->SEEKSTART);
	s := getline(in);
	if(s != "xref")
		return (nil, nil, sprint("bad value (%q), 'xref' expected", s));
	for(s = getline(in); s != "trailer"; s = getline(in)) {
		(s1, s2) := str->splitstrl(s, " ");
		if(s2 == nil)
			return (nil, nil, sprint("bad value (%q), 'start count' expected", s));
		start := int s1;
		no := int s2;
		newobjs := array[no] of (big, int, int, int);
		have := 0;
		for(j := 0; j < no; j++) {
			s = getline(in);
			if(len s != 19 && len s != 18)
				return (nil, nil, sprint("bad value (%q), xref entry expected", s));
			offset := big s[0:10];
			gen := int s[11:16];
			mode := 0;
			if(s[17] == 'n')
				mode = 1;
			if(s[17] != 'n' && s[17] != 'f')
				return (nil, nil, sprint("bad value (%q), expected 'f' or 'n'", s[17:18]));
			objloc := Objloc(offset, start+j, gen, mode);
			if(isnewobj(objs, objloc))
				newobjs[have++] = objloc;
		}
		newobjs = newobjs[:have];
		nobjs := array[len objs+len newobjs] of (big, int, int, int);
		nobjs[:] = objs;
		nobjs[len objs:] = newobjs;
		objs = nobjs;
	}

say(sprint("after trailer, offset=%bd", in.offset()));
	(tobj, err) := readtype(in, 0);
	if(err != nil)
		return (nil, nil, "reading trailer object: "+err);
	trailobj: ref Obj.Dict;
	pick t := tobj {
	Dict =>	trailobj = t;
	* =>	return (nil, nil, "bad trailing object, not a string");
	}

	(prev, nil) := trailobj.getint("Prev", Single);
	if(prev != nil) {
		err: string;
		(objs, nil, err) = readtrailer(in, int prev[0].orig, objs);
		if(err != nil)
			return (nil, nil, err);
	}
	return (objs, trailobj, nil);
}

getline(in: ref Input): string
{
	s := "";
	for(;;) {
		c := in.getb();
		if(c == '\r') {
			c = in.getb();
			if(c != '\n')
				in.ungetb();
			break;
		}
		if(c == '\n')
			break;
		s[len s] = c;
	}
	return s;
}

getstring(in: ref Input): string
{
	return readoperator(in).t0.s;
}

getnum(in: ref Input): int
{
	return int getstring(in);
}

Str.eq(n1: self Str, n2: Str): int
{
	if(len n1.a != len n2.a)
		return 0;
	for(i := 0; i < len n1.a; i++)
		if(n1.a[i] != n2.a[i])
			return 0;
	return 1;
}

tohex(a: array of byte): string
{
	s := "";
	for(i := 0; i < len a; i++)
		s += sprint("%02X", int a[i]);
	return s;
}

Str.text(s: self Str): string
{
	# xxx handle binary data
	#for(i := 0; i < len s.a; i++)
	#	if(s.a[i] < byte ' ' || s.a[i] >= byte 16r7f)
	#		return tohex(s.a);
	#return string s.a;

	r := "";
	for(i := 0; i < len s.a; i++)
		if(s.a[i] < byte ' ' || s.a[i] >= byte 16r7f)
			r += sprint("\\x%02x", int s.a[i]);
		else
			r[len r] = int s.a[i];
	return r;
}

objtext(oo: ref Obj, indent: int): string
{
	l := sprint("%*s", indent, "");
	pick o := oo {
	Boolean =>	return l+"bool:"+string o.v;
	Numeric =>	return l+"num:"+o.orig;
	Name =>		return l+"name:"+o.s.text();
	String =>	return l+"string:"+o.s.text();
	Dict =>		s := l+"dict:[\n";
			for(i := 0; i < len o.d; i++) {
				(k, v) := o.d[i];
				s += l+k.text()+":\t"+objtext(v, indent+1)+"\n";
			}
			s += l+"]";
			return s;
	Array =>	s := l+"array:[\n";
			for(i := 0; i < len o.a; i++)
				s += l+objtext(o.a[i], indent+1)+"\n";
			s += l+"]";
			return s;
	Objref =>	return l+"objref:"+string o.id+","+string o.gen;
	Operator =>	return l+"op:"+o.s;
	Null =>		return l+"null:";
	Stream =>	return l+"stream:("+o.d.text()+", "+o.s.text()+")";
	* =>		raise "fail:missing case";
	}
}

Obj.text(oo: self ref Obj): string
{
	return objtext(oo, 0);
}

Obj.pack(oo: self ref Obj): string
{
	pick o := oo {
	Boolean =>	if(o.v)
				return "true";
			return "false";
	Numeric =>	return o.orig;
	Name =>		return "/"+o.s.text(); # xxx escape special chars with hexadecimal encoding...
	String =>	return "("+o.s.text()+")";	# xxx escape special chars with backslash
	Dict =>		s := "<<";
			for(i := 0; i < len o.d; i++) {
				(k, v) := o.d[i];
				s += k.text()+"\t"+v.pack()+" ";
			}
			if(len s > 2)
				s = s[:len s-1];
			s += ">>";
			return s;
	Array =>	s := "[";
			for(i := 0; i < len o.a; i++)
				s += o.a[i].pack()+" ";
			if(len s > 1)
				s = s[:len s-1];
			s += "]";
			return s;
	Objref =>	return sprint("%d %d R", o.id, o.gen);
	Operator =>	return o.s;
	Null =>		return "null";
	Stream =>	return "stream\nbogus\nendstream\n";
	* =>		raise "fail:missing case";
	}
}

Doc.findobj(d: self ref Doc, id, gen: int): ref Objloc
{
	for(i := 0; i < len d.objs; i++) {
		r := d.objs[i];
		if(r.id == id && r.gen == gen)
			return ref r;
	}
	return nil;
}

readws(in: ref Input)
{
#say("readws");
	for(;;)
		case in.getb() {
		'\0' or '\n' or '\r' or ' ' or '\t' or 16r0c =>
			continue;
		'%' =>
			getline(in);
		* =>	in.ungetb();
			return;
		}
}

addbyte(d: array of byte, nd: int, c: int): (array of byte, int)
{
	if(nd+1 >= len d) {
		newd := array[2+len d*3/2] of byte;
		newd[:] = d;
		d = newd;
	}
	d[nd++] = byte c;
	return (d, nd);
}

readstring(in: ref Input): (ref Obj.String, string)
{
#say("readstring");
	if(in.getb() != '(')
		return (nil, "not a string");
	level := 1;
	d := array[0] of byte;
	nd := 0;
Top:
	for(;;) {
		c := in.getb();
		case c {
		'(' =>	level++;
		'\r' =>
			c = '\n';
			c2 := in.getb();
			if(c2 != '\r')
				in.ungetb();
		'\\' =>
			c = in.getb();
			case c {
			'\\' =>	c = '\\';	
			'n' =>	c = '\n';
			'r' =>	c = '\r';
			't' =>	c = '\t';
			'b' =>	c = '\b';
			'f' =>	c = 16r0c;
			'(' =>	c = '(';
			')' =>	c = ')';
			'\r' => c = -1;
				c = in.getb();
				if(c != '\n')
					in.ungetb();
			'\n' => c = -1;
			'0' to '7' =>
				s := "";
				s[0] = c;
				c2 := in.getb();
				if(c2 < '0' || c2 > '7') {
					in.ungetb();
				} else {
					s[1] = c2;
					c3 := in.getb();
					if(c3 < '0' || c3 > '7')
						in.ungetb();
					else
						s[2] = c3;
				}
				if(len s == 3)
					s[0] &= 8r7;
				(c, nil) = str->toint(s, 8);
			'<' or '>' or '[' or ']' or '{' or '}' or '/' or '%' =>
				# this is a specification violation, but encountered in the wild (for [ and ] at least)
				;
			ERROR =>	return (nil, sprint("reading: %r"));
			EOF =>	return (nil, "premature eof");
			* =>	return (nil, sprint("bad escaped char: %d", c));
			}
		')' =>	level--;
			if(level == 0)
				break Top;
		* =>
			;
		ERROR =>
			return (nil, sprint("reading: %r"));
		EOF =>
			return (nil, "premature eof");
		}
		if(c != -1)
			(d, nd) = addbyte(d, nd, c);
	}
	return (ref Obj.String(Str(d[:nd]), 0), nil);
}

readarray(in: ref Input): (ref Obj.Array, string)
{
#say("readarray");
	c := in.getb();
	if(c != '[')
		return (nil, "missing '['");
	d := array[4] of ref Obj;
	nd := 0;
	for(;;) {
		readws(in);
		c = in.getb();
		if(c == ']')
			break;
		in.ungetb();

		c = in.getb();
		if(c == 'R') {
			if(nd < 2)
				return (nil, "bad reference");
			idobj := d[nd-2];
			genobj := d[nd-1];
			id, gen: int;
			pick o := idobj {
			Numeric =>	id = int o.orig;
			* =>	return (nil, "bad id type in reference");
			}
			pick o := genobj {
			Numeric =>	gen = int o.orig;
			* =>	return (nil, "bad gen type in reference");
			}
			nd -= 2;
			d[nd++] = ref Obj.Objref(id, gen);
#say("have indirect");
			continue;
		}
		in.ungetb();
		(obj, err) := readtype(in, 0);
		if(err != nil)
			return (nil, err);
		if(nd >= len d) {
			newd := array[2*nd] of ref Obj;
			newd[:] = d;
			d = newd;
		}
		d[nd++] = obj;
	}
	return (ref Obj.Array(d[:nd]), nil);
}

# '<' has already been consumed
readhexstring(in: ref Input): (ref Obj.String, string)
{
#say("readhexstring");
	d := array[0] of byte;
	nd := 0;
	t := "";
done:
	for(;;) {
		if(len t == 2) {
			(v, rem) := str->toint(t, 16);
			if(rem != nil)
				return (nil, sprint("non-hex bytes in hex string (%q)", t));
			addbyte(d, nd, v);
			t = "";
		}
		case c := in.getb() {
		'>' =>
			if(len t == 1) {
				t[len t] = '0';
				in.ungetb();
				continue;
			}
			break done;
		'A' to 'F' =>
			t[len t] = c+'a'-'A';
		'a' to 'f' or '0' to '9' =>
			t[len t] = c;
		ERROR =>	return (nil, sprint("reading: %r"));
		EOF =>		return (nil, "premature eof");
		}
	}
	return (ref Obj.String(Str(d[:nd]), 1), nil);
}

readnumeric(in: ref Input): (ref Obj, string)
{
#say("readnumeric");
	s := "";
	isreal := 0;
Top:
	for(;;) {
		c := in.getb();
		case c {
		'+' or '-' =>
			if(len s != 0)
				return (nil, sprint("bad numeric: %c after first char", c));
		'0' to '9' =>
			;
		'.' =>
			if(isreal)
				return (nil, sprint("bad real, multiple decimal points"));
			isreal = 1;
		* =>
			in.ungetb();
			break Top;
		ERROR =>
			return (nil, sprint("reading: %r"));
		}
		s[len s] = c;
	}
#say(sprint("readnumeric, s=%q", s));
	return (ref Obj.Numeric(real s, s), nil);
}

# first '<' has already been consumed
readdict(in: ref Input): (ref Obj, string)
{
#say("readdict");
	d := array[0] of (Str, ref Obj);
	c := in.getb();
	if(c != '<')
		return (nil, "dict does not start with '<<'");
	for(;;) {
		readws(in);
		c = in.getb();
#say(sprint("dict, have c=%c", c));
		if(c == '>') {
			c = in.getb();
			if(c != '>')
				return (nil, "bad end of dict");
			break;
		}
		in.ungetb();
		(k, kerr) := readtype(in, 0);
		if(kerr != nil)
			return (nil, "reading elem in dict: "+kerr);
		key: Str;
		pick sk := k {
		Name =>	key = sk.s;
		Numeric =>
			# must be an object reference
			if(len d == 0)
				return (nil, "dict: bad key (not a name)");
			gen := int sk.orig;
			id: int;
			pick vk := d[len d-1].t1 {
			Numeric =>
				id = int vk.orig;
			* =>	return (nil, "dict: bad key, bad indirect");
			}
			readws(in);
			c = in.getb();
			if(c != 'R')
				return (nil, "dict: bad indirect");
			d[len d-1].t1 = ref Obj.Objref(id, gen);
#say("have indirect");
			continue;
		* =>	return (nil, "dict: bad key (not a name)");
		}
		readws(in);
		(v, verr) := readtype(in, 0);
		if(verr != nil)
			return (nil, "reading dict: "+verr);
		nd := array[len d+1] of (Str, ref Obj);
		nd[:] = d;
		nd[len d] = (key, v);
		d = nd;
	}
	return (ref Obj.Dict(d), nil);
}

gethex(in: ref Input): int
{
	c := in.getb();
	if(c >= '0' && c <= '9' || c >= 'a' && c <= 'f')
		return c;
	if(c >= 'A' && c <= 'F')
		return c+('a'-'A');
	return 0;
}

readname(in: ref Input): (ref Obj.Name, string)
{
#say("readname");
	c := in.getb();
	if(c != '/')
		return (nil, "missing '/' at start of name");
	d := array[0] of byte;
	nd := 0;
Top:
	for(;;) {
		c = in.getb();
		case c {
		'#' =>
			c1 := gethex(in);
			c2 := gethex(in);
			if(!c1 || !c2)
				return (nil, "bad hexadecimal in name");
			s: string;
			s[0] = c1;
			s[1] = c2;
			(v, nil) := str->toint(s, 16);
			if(v == 0)
				return (nil, "invalid byte \\0 in name");
			(d, nd) = addbyte(d, nd, v);
		'(' or ')' or '<' or '>' or '[' or ']' or '{' or '}' or '/' or '%' or '\0' or '\n' or '\r' or ' ' or '\t' or 16r0c or EOF =>
			in.ungetb();
			break Top;
		ERROR =>
			return (nil, sprint("reading: %r"));
		* =>
			(d, nd) = addbyte(d, nd, c);
		}
	}
	return (ref Obj.Name(Str(d[:nd])), nil);
}

readoperator(in: ref Input): (ref Obj.Operator, string)
{
	s := "";
done:
	for(;;)
		case c := in.getb() {
		'(' or ')' or '<' or '>' or '[' or ']' or '{' or '}' or '/' or '%' or '\0' or '\n' or '\r' or ' ' or '\t' or 16r0c or EOF =>
			in.ungetb();
			break done;
		* =>
			s[len s] = c;
		ERROR =>	return (nil, sprint("reading: %r"));
		}
	obj := ref Obj.Operator(s);
	if(s == nil)
		obj = nil;
	return (obj, nil);
}

readtype(in: ref Input, op: int): (ref Obj, string)
{
#say(sprint("readtype, offset=%bd", in.offset()));
	if(op)
		readws(in);
	c := in.getb();
	in.ungetb();

	t: (ref Obj, string);
	case c {
	'(' =>	t = readstring(in);
	'[' =>	t = readarray(in);
	'.' or '0' to '9' or '-' or '+' =>	t = readnumeric(in);
	'/' =>	t = readname(in);
	'<' =>
		in.getb();
		c = in.getb();
		in.ungetb();
		if(c == '<')
			t = readdict(in);
		else
			t = readhexstring(in);
	* =>
		t = (o, err) := readoperator(in);
		if(err != nil && o != nil) {
			case o.s {
			"true" or "false" =>
				t = (ref Obj.Boolean(o.s == "true"), nil);
			"null" =>
				t = (ref Obj.Null(), nil);
			* =>
				if(!op)
					return (nil, sprint("bad character (%c)", c));
			}
		}
	EOF =>		return (nil, nil);	# xxx not handled when it happens outside reading a pages contents
	ERROR =>	return (nil, sprint("reading: %r"));
	}
	if(t.t0 != nil && (tagof t.t0 == tagof Obj.Name || tagof t.t0 == tagof Obj.Operator))
		; #say(sprint("have name=%q", t.t0.text()));
	return t;
}

getnumber(d: ref Doc, oo: ref Obj.Dict, s: string): (int, string)
{
	(v, err) := oo.find(s);
	if(err != nil)
		return (0, err);
	pick o := v {
	Numeric =>
		return (int o.orig, nil);
	Objref =>
		offset := d.in.offset();
		(refo, derr) := d.deref(o);
		d.in.seek(offset, Bufio->SEEKSTART);
		if(err != nil)
			return (0, derr);
		pick numo := refo {
		Numeric =>
			return (int numo.orig, nil);
		* =>
			return (0, "bad type, referenced type was not num");
		}
	* =>
		return (0, "bad type, not int or objref");
	}
}

Doc.readobj(d: self ref Doc, ol: ref Objloc): (ref Obj, string)
{
#say(sprint("offset=%bd", ol.offset));
	in := d.in;
	in.seek(ol.offset, Bufio->SEEKSTART);
	readws(in);
	id := getnum(in);
	readws(in);
	gen := getnum(in);
	if(id != ol.id || gen != ol.gen)
		return (nil, sprint("object id (%d, %d) or generation number (%d, %d) do not match", id, ol.id, gen, ol.gen));
	readws(in);
	s := getstring(in);
	if(s != "obj")
		return (nil, sprint("bad token %#q, expected 'obj'", s));
	readws(in);
	(obj, err) := readtype(in, 0);
	if(err != nil)
		return (nil, err);
	readws(in);
	s = getstring(in);
	if(s == "stream") {
		pick dobj := obj {
		Dict =>
#say(sprint("offset before length=%bd", in.offset()));
			(length, lerr) := getnumber(d, dobj, "Length");
			if(lerr != nil)
				return (nil, lerr);
			c := in.getb();
			if(c == '\r')
				c = in.getb();
			if(c != '\n')
				return (nil, sprint("expected newline after 'stream', found '%d'", c));
#say(sprint("before read, offset=%bd length=%d", in.offset(), length));

			start := in.offset();
			in.seek(big length, Bufio->SEEKRELA);
			readws(in);
#say(sprint("after readws, offset=%bd", in.offset()));
			s = getstring(in);
			if(s != "endstream")
				return (nil, sprint("expected 'endstream', found %#q", s));

			(names, nerr) := dobj.getname("Filter", Single|Many);
			if(nerr == "key not present") # xxx ugly
				names = array[0] of ref Obj.Name;
			else if(nerr != nil)
				return (nil, nerr+" "+dobj.text());

			(stream, serr) := makestream(names, d.fd, start, start+big length);
			if(serr != nil)
				return (nil, sprint("making filter: %s", serr));
			obj = ref Obj.Stream(dobj, stream);

		* =>
			return (nil, "not a dict before stream");
		}
		readws(in);
		s = getstring(in);
	}
	if(s != "endobj")
		return (nil, sprint("bad token %#q, expected 'endobj'", s));
	return (obj, nil);
}

Doc.deref(d: self ref Doc, o: ref Obj.Objref): (ref Obj, string)
{
	ol := d.findobj(o.id, o.gen);
	if(ol == nil)
		return (nil, sprint("object (%d, %d) not in xref table", o.id, o.gen));
	return d.readobj(ol);
}

makestream(names: array of ref Obj.Name, fd: ref Sys->FD, start, end: big): (ref Input.Stream, string)
{
	fname := ":";
	for(i := 0; i < len names; i++) {
		case f := names[i].s.text() {
		"FlateDecode" =>
			fname += ",pdfinflate:";
		"LZWDecode" =>
			fname += ",lzwdecode:";
		"ASCII85Decode" =>
			fname += ",ascii85decode:";
		"ASCIIHexDecode" =>
			fname += ",asciihexdecode:";
		* =>
			return (nil, sprint("unknown decoder: %s", f));
		}
	}
	
	rq := cascadefilter->start(fname);
	if(rq == nil)
		return (nil, "error creating cascadede filter");
	stream := Input.mk(fd, start, end, names, rq);
	pick m := <- rq {
	Start =>	stream.fpid = m.pid;
	* =>		return (nil, "bad first message from filter");
	}
	return (stream, nil);
}

Obj.find(oo: self ref Obj, s: string): (ref Obj, string)
{
	pick o := oo {
	Dict =>
		robj: ref Obj;
		k := Str(array of byte s);
		for(i := 0; i < len o.d; i++)
			if(o.d[i].t0.eq(k) && tagof o.d[i].t1 != tagof Obj.Null) {
				if(robj != nil)
					return (nil, "key not present");
				robj = o.d[i].t1;
			}
		if(robj == nil)
			return (nil, "key not present");
		return (robj, nil);
	* =>
		return (nil, "not a dict");
	}
}

Obj.get(oo: self ref Obj, s: string, which, t: int): (array of ref Obj, string)
{
	single := which&Single;
	many := which&Many;
	if(!single && !many)
		return (nil, "find: bad arguments");
	(ooo, err) := oo.find(s);
	if(err != nil)
		return (nil, err);
	pick o := ooo {
	Array =>
		if(!many) {
			if(t != tagof Obj.Array)
				return (nil, "object is array");
			return (o.a, nil);
		}
		for(j := 0; j < len o.a; j++)
			if(tagof o.a[j] != t)
				return (nil, sprint("object %d in array of wrong type", j));
		return (o.a, nil);
	* =>
		if(tagof o != t)
			return (nil, "bad type of object");
		if(!single)
			return (nil, "object returned is not an array");
		return (array[] of {o}, nil);
	}
}

Obj.getobjref(oo: self ref Obj, s: string, which: int): (array of ref Obj.Objref, string)
{
	(a, err) := oo.get(s, which, tagof Obj.Objref);
	if(err != nil)
		return (nil, err);
	ta := array[len a] of ref Obj.Objref;
	for(i := 0; i < len a; i++)
		pick obj := a[i] {
		Objref =>	ta[i] = obj;
		}
	return (ta, nil);
}

Obj.getint(oo: self ref Obj, s: string, which: int): (array of ref Obj.Numeric, string)
{
	(a, err) := oo.get(s, which, tagof Obj.Numeric);
	if(err != nil)
		return (nil, err);
	ta := array[len a] of ref Obj.Numeric;
	for(i := 0; i < len a; i++)
		pick obj := a[i] {
		Numeric =>	ta[i] = obj;
		}
	return (ta, nil);
}

Obj.getname(oo: self ref Obj, s: string, which: int): (array of ref Obj.Name, string)
{
	(a, err) := oo.get(s, which, tagof Obj.Name);
	if(err != nil)
		return (nil, err);
	ta := array[len a] of ref Obj.Name;
	for(i := 0; i < len a; i++)
		pick obj := a[i] {
		Name =>	ta[i] = obj;
		}
	return (ta, nil);
}

Input.mk(fd: ref Sys->FD, start, end: big, fnames: array of ref Obj.Name, rq: chan of ref Filter->Rq): ref Input.Stream
{
	return ref Input.Stream(fd, start, start, end, 0, rq, 0, -1, fnames, 0, array[0] of byte, 0, -1, 0);
}

Input.seek(ii: self ref Input, n: big, where: int): big
{
	pick i := ii {
	File =>
		return i.b.seek(n, where);
	Stream =>
say("seek on Input.Stream");
raise "fail:seek on Input.Stream";
		return big 0;
	}
}

Input.offset(ii: self ref Input): big
{
	pick i := ii {
	File =>
		return i.b.offset();
	Stream =>
		return big i.foff;
	}
}

filterget(i: ref Input.Stream)
{
	for(;;)
		pick m := <-i.rq {
		Start =>
			;
		Fill =>
			n := len m.buf;
			can := int (i.end-i.off);
			if(n > can)
				n = can;
			have := sys->pread(i.fd, m.buf, n, i.off);
			if(have < 0) {
				i.err = 1;
				return;
			}
			m.reply <-= have;
			i.off += big have;
		Result =>
#sys->print("have data: %s\n", string m.buf);
			i.d = array[len m.buf] of byte;
			i.d[:] = m.buf;
			i.doff = 0;
			m.reply <-= 0;
			return;
		Finished =>
			i.eof = 1;
			i.d = array[0] of byte;
			i.doff = 0;
			if(len m.buf > 0)
				say(sprint("leftover data, %d bytes", len m.buf));
			return;
		Info =>
			;
		Error =>
			i.err = 1;
			sys->werrstr(sprint("filter: %s", m.e));
			say(sprint("error from filter: %s", m.e));
			return;
		}
}

Input.getb(ii: self ref Input): int
{
	pick i := ii {
	File =>
		return i.b.getb();
	Stream =>
#sys->print("getb\n");
		if(i.err)
			return ERROR;
		if(i.eof)
			return EOF;
		if(i.unget) {
			i.unget = 0;
			i.foff++;
#sys->print("returning from unget buffer, i.prev=%d\n", i.prev);
			return i.prev;
		}
		if(i.doff >= len i.d) {
			filterget(i);
			if(i.err)
				return ERROR;
		}
		if(i.doff >= len i.d) {
			i.eof = 1;
			return EOF;
		}
		i.foff++;
		i.prev = int i.d[i.doff++];
#sys->print("returning from buf, i.prev=%d\n", i.prev);
		return i.prev;
	}
}

Input.ungetb(ii: self ref Input): int
{
	pick i := ii {
	File =>
		return i.b.ungetb();
	Stream =>
		if(i.err)
			return ERROR;
		if(i.eof)
			return EOF;
		if(i.unget) {
			sys->werrstr("two consecutive ungetb's");
			return ERROR;
		}
		i.foff--;
		i.unget = 1;
#sys->print("ungetb, returning %d\n", i.prev);
		return i.prev;
	}
}

Input.text(ii: self ref Input): string
{
	pick i := ii {
	File =>
		return "input:bufio";
	Stream =>
		return sprint("input:stream(start=%bd off=%bd end=%bd foff=%d err=%d eof=%d unget=%d)", i.start, i.off, i.end, i.foff, i.err, i.eof, i.unget);
	}
}

Input.rewind(ii: self ref Input): string
{
	pick i := ii {
	File =>
		raise "rewind on bufio"; # xxx should implement this
	Stream =>
		(stream, err) := makestream(i.fnames, i.fd, i.start, i.end);
		if(err != nil)
			return err;
		*i = *stream;
		return nil;
	}
}

say(s: string)
{
	if(dflag)
		sys->fprint(sys->fildes(2), "%s\n", s);
}

Pdfread: module {
	PATH:	con "/dis/lib/pdfread.dis";

	dflag: int;

	init:	fn();

	Single, Many:	con 1+iota;

	Str: adt {
		a: array of byte;

		eq:	fn(n1: self Str, n2: Str): int;
		text:	fn(s: self Str): string;
	};

	Input: adt {
		pick {
		File =>
			b:	ref Iobuf;
		Stream =>
			fd:	ref Sys->FD;
			start, off, end:	big;
			
			err:	int;
			rq:	chan of ref Filter->Rq;
			foff:	int;
			fpid:	int;
			fnames:	array of ref Obj.Name;
			eof:	int;
			d:	array of byte;
			doff:	int;
			prev:	int;
			unget:	int;
		}

		mk:	fn(fd: ref Sys->FD, start, end: big, fnames: array of ref Obj.Name, rq: chan of ref Filter->Rq): ref Input.Stream;

		seek:	fn(i: self ref Input, n: big, where: int): big;
		offset:	fn(i: self ref Input): big;
		getb:	fn(i: self ref Input): int;
		ungetb:	fn(i: self ref Input): int;
		text:	fn(i: self ref Input): string;
		rewind:	fn(i: self ref Input): string;
	};

	Obj: adt {
		pick {
		Boolean =>
			v: int;
		Numeric =>
			v: real;
			orig: string;
		String =>
			s: Str;
			hex: int;
		Name =>
			s: Str;
		Dict =>
			d: cyclic array of (Str, ref Obj);
		Array =>
			a: cyclic array of ref Obj;
		Objref =>
			id, gen:	int;
		Operator =>
			s: string;
		Null =>
		Stream =>
			d:	cyclic ref Obj.Dict;
			s:	ref Input.Stream;
		}

		find:		fn(o: self ref Obj, s: string): (ref Obj, string);
		get:		fn(o: self ref Obj, s: string, which, t: int): (array of ref Obj, string);
		getint:		fn(o: self ref Obj, s: string, which: int): (array of ref Obj.Numeric, string);
		getname:	fn(o: self ref Obj, s: string, which: int): (array of ref Obj.Name, string);
		getobjref:	fn(o: self ref Obj, s: string, which: int): (array of ref Obj.Objref, string);
		text:	fn(o: self ref Obj): string;
		pack:	fn(o: self ref Obj): string;
	};

	Objloc: adt {
		offset: big;
		id, gen, inuse: int;
	};

	Doc: adt {
		fd:	ref Sys->FD;
		b:	ref Iobuf;
		in:	ref Input;
		version:	string;
		xref:	int;
		trailer:	ref Obj.Dict;
		objs:	array of Objloc;

		open:	fn(path: string): (ref Doc, string);
		findobj:	fn(d: self ref Doc, id, gen: int): ref Objloc;
		readobj:	fn(d: self ref Doc, ol: ref Objloc): (ref Obj, string);
		deref:		fn(d: self ref Doc, o: ref Obj.Objref): (ref Obj, string);
	};

	readtype:	fn(in: ref Input, op: int): (ref Obj, string);
};

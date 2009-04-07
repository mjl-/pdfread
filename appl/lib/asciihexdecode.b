# for reading the ASCIIHexDecode in pdf files
# see adobe's pdf reference

implement Filter;

include "sys.m";
	sys: Sys;
include "string.m";
	str: String;
include "filter.m";


EOF:	con -1;
ABORT:	con -2;

Dec: adt {
	params:	string;
	bufin, bufout:	array of byte;
	nin, nout, offin: int;
	c:	chan of ref Rq;
	rc:	chan of int;
};

init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
}

start(params: string): chan of ref Rq
{
	d := ref Dec(params, array[2*1024] of byte, array[2*1024] of byte, 0, 0, 0, chan of ref Rq, chan of int);
	spawn asciihexdecode(d);
	return d.c;
}


asciihexdecode(d: ref Dec) 
{
	d.c <-= ref Rq.Start(sys->pctl(0, nil));

	s := "";
done:
	for(;;) {
		case c := getb(d) {
		EOF =>
			d.c <-= ref Rq.Error("premature eof");
			return;
		ABORT =>
			return;
		'\0' or '\n' or '\r' or ' ' or '\t' or 16r0c =>
			;
		'0' to '9' or 'a' to 'f' or 'A' to 'F' =>
			s[len s] = c;
			if(len s == 2) {
				if(!put(d, s))
					return;
				s = "";
			}
		'>' =>
			if(s != "")
				s += "0";
			if(!put(d, s))	
				return;
			break done;
		* =>
			d.c <-= ref Rq.Error(sys->sprint("invalid input: byte 0x%x", c));
		}
	}
	if(d.nout > 0) {
		d.c <-= ref Rq.Result(d.bufout[:d.nout], d.rc);
		if((<-d.rc) == -1)
			return;
	}
	d.c <-= ref Rq.Finished(d.bufin[:d.nin-d.offin]);
}

put(d: ref Dec, s: string): int
{
	(v, nil) := str->toint(s, 16);
	r := "";
	r[0] = v;
	a := array of byte r;
	if(d.nout+len a > len d.bufout) {
		d.c <-= ref Rq.Result(d.bufout[:d.nout], d.rc);
		if((<-d.rc) == -1)
			return 0;
		d.nout = 0;
	}
	d.bufout[d.nout:] = a;
	d.nout += len a;
	return 1;
}

fill(d: ref Dec): int
{
	d.c <-= ref Rq.Fill(d.bufin, d.rc);
	n := <-d.rc;
	if(n >= 0) {
		d.nin = n;
		d.offin = 0;
	}
	case n {
	0 =>	return EOF;
	-1 =>	return ABORT;
	* =>	return n;
	}
}

getb(d: ref Dec): int
{
	if(d.offin == d.nin) {
		n := fill(d);
		if(n == ABORT || n == EOF)
			return n;
	}
	return int d.bufin[d.offin++];
}

# for reading the ASCII85Decode in pdf files
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
	vflag: int;
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
	vflag := len params > 0 && params[0] == 'v';
	d := ref Dec(params, vflag, array[2*1024] of byte, array[2*1024] of byte, 0, 0, 0, chan of ref Rq, chan of int);
	spawn ascii85decode(d);
	return d.c;
}

error(d: ref Dec, s: string)
{
	d.c <-= ref Rq.Error(s);
}

ascii85decode(d: ref Dec) 
{
	d.c <-= ref Rq.Start(sys->pctl(0, nil));

	s := "";
done:
	for(;;) {
		case c := getb(d) {
		EOF =>
			error(d, "premature eof");
			return;
		ABORT =>
			return;
		'\0' or '\n' or '\r' or ' ' or '\t' or 16r0c =>
			;
		'!' to 'u' or 'z' =>
			if(c == 'z') {
				if(len s != 0) {
					error(d, "z in middle of group");
					return;
				}
				if(!put(d, "!!!!!"))
					return;
				s = "";
				continue;
			}

			s[len s] = c;
			if(len s == 5) {
				if(!put(d, s))
					return;
				s = "";
			}
		'~' =>
			c = getb(d);
			if(c != '>') {
				error(d, "bad character: '~' not followed by '>'");
				return;
			}
			if(s != "") {
				if(len s == 1) {
					error(d, "bad final group with one character");
					return;
				}
				if(!put(d, s))	
					return;
			}
			break done;
		* =>
			error(d, sys->sprint("invalid input: byte 0x%x", c));
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
	if(d.vflag) d.c <-= ref Rq.Info(sys->sprint("doing s=%q", s));
	n := len s-1;
	while(len s < 5)
		s[len s] = '!';
	v := big 0;
	for(i := 0; i < len s; i++)
		v = big 85*v+big (s[i]-'!');
	a := array[4] of {byte (v>>24), byte (v>>16), byte (v>>8), byte v};
	a = a[:n];
	if(d.vflag) d.c <-= ref Rq.Info(sys->sprint("v=%bd n=%d", big v, n));

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

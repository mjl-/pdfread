# written for reading the lzw encoding found in pdf files
# http://www.cs.duke.edu/csed/curious/compression/lzw.html
# http://en.wikipedia.org/wiki/LZW

implement Filter;

include "sys.m";
	sys: Sys;
include "filter.m";


EOF:	con -1;
ABORT:	con -2;

FLUSH:	con 256;
EOD:	con 257;
LASTFIXED:	con EOD;

LZWstate: adt {
	params:	string;
	tab:	array of array of byte;
	last, width, have, v:	int;
	prev:	array of byte;
	bufin, bufout:	array of byte;
	nin, nout:	int;
	offin:	int;
	c:	chan of ref Rq;
	rc:	chan of int;
};

init()
{
	sys = load Sys Sys->PATH;
}

start(params: string): chan of ref Rq
{
	tab := array[4096] of array of byte;
	for(i := 0; i < 256; i++)
		tab[i] = array of byte sys->sprint("%c", i);
	c := chan of ref Rq;
	rc := chan of int;
	lzw := ref LZWstate(params, tab, LASTFIXED, 9, 0, 0, array[0] of byte, array[2*1024] of byte, array[8*1024] of byte, 0, 0, 0, c, rc);
	spawn lzwdecode(lzw);
	return lzw.c;
}

lzwdecode(lzw: ref LZWstate)
{
	lzw.c <-= ref Rq.Start(sys->pctl(0, nil));

	bits := 0;
done:
	for(;;) {
		width := lzw.width;
		case i := getn(lzw) {
		EOF =>
			#lzw.c <-= ref Rq.Error("premature eof");
			#return;
			# it seems eof without EOD occurs in practice
			break done;
		ABORT =>
			return;
		FLUSH =>
			lzw.width = 9;
			lzw.last = LASTFIXED;
			lzw.prev = array[0] of byte;
		EOD =>
			break done;
		* =>
			if(i > lzw.last+1) {
				lzw.c <-= ref Rq.Error(sys->sprint("bad reference %d, last possible is %d (offset %d bits, width=%d bits)", i, lzw.last+1, bits, lzw.width));
				return;
			}
			if(i > lzw.last) {
				e := array[len lzw.prev+1] of byte;
				e[:] = lzw.prev;
				e[len lzw.prev:] = lzw.prev[0:1];
				lzw.tab[++lzw.last] = e;
			}
			else if(len lzw.prev != 0 && lzw.last < len lzw.tab-1) {
				e := array[len lzw.prev+1] of byte;
				e[:] = lzw.prev;
				e[len lzw.prev:] = lzw.tab[i][0:1];
				lzw.tab[++lzw.last] = e;
			}
			if(lzw.last == 510 || lzw.last == 1022 || lzw.last == 2046)
				lzw.width++;
			lzw.prev = lzw.tab[i];
			if(!puts(lzw, lzw.prev))
				return;
		}
		bits += width;
	}
	if(lzw.nout > 0) {
		lzw.c <-= ref Rq.Result(lzw.bufout[:lzw.nout], lzw.rc);
		if((<-lzw.rc) == -1)
			return;
	}
	lzw.c <-= ref Rq.Finished(lzw.bufin[:lzw.nin-lzw.offin]);
}

puts(lzw: ref LZWstate, a: array of byte): int
{
	if(lzw.nout+len a > len lzw.bufout) {
		lzw.c <-= ref Rq.Result(lzw.bufout[:lzw.nout], lzw.rc);
		if((<-lzw.rc) == -1)
			return 0;
		lzw.nout = 0;
	}
	lzw.bufout[lzw.nout:] = a;
	lzw.nout += len a;
	return 1;
}

fill(lzw: ref LZWstate): int
{
	lzw.c <-= ref Rq.Fill(lzw.bufin, lzw.rc);
	n := <-lzw.rc;
	if(n >= 0) {
		lzw.nin = n;
		lzw.offin = 0;
	}
	case n {
	0 =>	return EOF;
	-1 =>	return ABORT;
	* =>	return n;
	}
}

getb(lzw: ref LZWstate): int
{
	if(lzw.offin == lzw.nin) {
		n := fill(lzw);
		if(n == ABORT || n == EOF)
			return n;
	}
	return int lzw.bufin[lzw.offin++];
}

getn(lzw: ref LZWstate): int
{
	while(lzw.have < lzw.width) {
		c := getb(lzw);
		if(c == EOF || c == ABORT)
			return c;
		lzw.v = (lzw.v<<8) | c;
		lzw.have += 8;
	}
	r := lzw.v>>(lzw.have-lzw.width);
	lzw.have -= lzw.width;
	lzw.v &= (1<<lzw.have)-1;
	return r;
}

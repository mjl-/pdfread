# for convenience, passes all data through unmodified

implement Filter;

include "sys.m";
	sys: Sys;
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
}

start(params: string): chan of ref Rq
{
	d := ref Dec(params, array[2*1024] of byte, array[2*1024] of byte, 0, 0, 0, chan of ref Rq, chan of int);
	spawn nullfilter(d);
	return d.c;
}

nullfilter(d: ref Dec) 
{
	d.c <-= ref Rq.Start(sys->pctl(0, nil));

done:
	for(;;) {
		case c := getb(d) {
		EOF =>
			break done;
		ABORT =>
			return;
		* =>
			if(!put(d, c))
				return;
		}
	}
	if(d.nout > 0) {
		d.c <-= ref Rq.Result(d.bufout[:d.nout], d.rc);
		if((<-d.rc) == -1)
			return;
	}
	d.c <-= ref Rq.Finished(d.bufin[:d.nin-d.offin]);
}

put(d: ref Dec, c: int): int
{
	if(d.nout+1 > len d.bufout) {
		d.c <-= ref Rq.Result(d.bufout[:d.nout], d.rc);
		if((<-d.rc) == -1)
			return 0;
		d.nout = 0;
	}
	d.bufout[d.nout++] = byte c;
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

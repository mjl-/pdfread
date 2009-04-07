# filters cascaded into one filter

# xxx load each filter only once

implement Filter;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "string.m";
	str: String;
include "filter.m";
	nullfilter: Filter;


ABORT:	con -1;
FINISHED:	con -2;

Top: adt {
	params:	string;
	vflag:	int;
	f:	array of ref F;
	bufin, bufout:	array of byte;
	nin, nout, offin: int;
	c:	chan of ref Rq;
	rc:	chan of int;
};

F: adt {
	params:	string;
	name:	string;
	pid:	int;
	i:	int;
	done:	int;
	prev:	cyclic ref F;
	bufout:	array of byte;
	c:	chan of ref Rq;

	get:	fn(f: self ref F, t: ref Top, buf: array of byte): (int, array of byte);
};

init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	nullfilter = load Filter "/dis/lib/nullfilter.dis";
	nullfilter->init();
}

start(params: string): chan of ref Rq
{
	if(params == "" || params == ":" || params == ":," || params == ":v,")
		return nullfilter->start("");

	f := array[0] of ref F;
	vflag := 0;
	i := 0;
	while(params != "") {
		s: string;
		(s, params) = str->splitstrl(params, ",");
		if(params != nil)
			params = params[1:];
		(name, param) := str->splitstrl(s, ":");
		if(param != nil)
			param = param[1:];
		if(name == nil) {
			if(param != nil && param[0] == 'v')
				vflag = 1;
			continue;
		}
		p := "";
		case name {
		"deflate" =>	p = Filter->DEFLATEPATH;
		"inflate" =>	p = Filter->INFLATEPATH;
		"pdfinflate" =>	p = "/dis/lib/pdfinflate.dis";
		"slip" =>	p = Filter->SLIPPATH;
		"null" =>	p = "/dis/lib/nullfilter.dis";
		"lzwdecode" =>	p = "/dis/lib/lzwdecode.dis";
		"asciihexdecode" =>	p = "/dis/lib/asciihexdecode.dis";
		"ascii85decode" =>	p = "/dis/lib/ascii85decode.dis";
		* =>	return nil;
		}
		mod := load Filter p;
		if(mod == nil)
			return nil;
		mod->init();

		if(len f == 0 && params == "")
			return mod->start(param);

		fc := mod->start(param);
		if(fc == nil)
			return nil;
		pid: int;
		pick m := <-fc {
		Start =>	pid = m.pid;
		* =>	return nil;
		}
		prev: ref F;
		if(len f > 0)
			prev = f[len f-1];
		fil := ref F(params, name, pid, i++, 0, prev, array[0] of byte, fc);

		nf := array[len f+1] of ref F;
		nf[:] = f;
		nf[len f] = fil;
		f = nf;
	}

	t := ref Top(params, vflag, f, array[2*1024] of byte, array[2*1024] of byte, 0, 0, 0, chan of ref Rq, chan of int);
	spawn cascadefilter(t);
	return t.c;
}

info(t: ref Top, s: string)
{
	t.c <-= ref Rq.Info(s);
}

cascadefilter(t: ref Top)
{
	t.c <-= ref Rq.Start(sys->pctl(0, nil));

	if(t.vflag) info(t, sprint("have %d filters", len t.f));

	l := t.f[len t.f-1];
	buf := array[8*1024] of byte;
	leftover: array of byte;
done:
	for(;;) {
		n: int;
		(n, leftover) = l.get(t, buf);
		if(t.vflag) info(t, sprint("l.get on last filter (%s), n=%d", l.name, n));
		case n {
		ABORT =>
			if(t.vflag) info(t, "last filter has abort from predecesor");
			return;
		FINISHED =>
			if(t.vflag) info(t, "last filter has eof from predecesor");
			break done;
		0 =>
			;
		* =>
			t.c <-= ref Rq.Result(buf[:n], t.rc);
			if((<-t.rc) == -1) {
				for(i := 0; i < len t.f; i++)
					kill(t.f[i].pid);
			}
		}
	}
	if(t.vflag) info(t, "last filter is finished");
	t.c <-= ref Rq.Finished(leftover);
}

kill(pid: int)
{
	fd := sys->open(sprint("/prog/%d/ctl", pid), sys->OWRITE);
	sys->fprint(fd, "kill");
}

text(msg: ref Rq): string
{
	pick m := msg {
	Fill =>		return sprint("Rq.Fill(len buf %d)", len m.buf);
	Result =>	return sprint("Rq.Result(len buf %d)", len m.buf);
	Finished =>	return sprint("Rq.Finished(len buf %d)", len m.buf);
	Info =>		return sprint("Rq.Info(%s)", m.msg);
	Error =>	return sprint("Rq.Error(%s)", m.e);
	* =>		return "unknown message";
	}
}

F.get(f: self ref F, t: ref Top, buf: array of byte): (int, array of byte)
{
	while(len f.bufout == 0) {
		msg := <-f.c;
		if(t.vflag) info(t, sprint("from filter %d name=%q, have msg %s", f.i, f.name, text(msg)));
		pick m := msg {
		Fill =>
			n: int;
			if(f.i == 0) {
				t.c <-= ref Rq.Fill(m.buf, t.rc);
				n = <-t.rc;
				m.reply <-= n;
				if(n < 0)
					return (ABORT, nil);
			} else {
				(n, nil) = t.f[f.i-1].get(t, m.buf);
				if(n == FINISHED)
					n = 0;
				m.reply <-= n;
				if(n == ABORT)
					return (ABORT, nil);
			}
		Result =>
			f.bufout = array[len m.buf] of byte;
			f.bufout[:] = m.buf;
			m.reply <-= 0;
		Finished =>
			if(len m.buf > 0)
				t.c <-= ref Rq.Info(f.name+": leftover data, "+string len m.buf+" bytes");
			f.done = 1;
			if(f.prev != nil && !f.prev.done) {
				pick m2 := <- f.prev.c {
				Finished =>
					f.prev.done = 1;
				* =>
					# or should this be treated as leftover data?
					if(t.vflag) info(t, sprint("finished, but previous filter was not yet done"));
					return (ABORT, nil);
				}
			}
			return (FINISHED, m.buf);
		Info =>
			t.c <-= ref Rq.Info("info: "+f.name+": "+m.msg);
		Error =>
			t.c <-= ref Rq.Error("error: "+f.name+": "+m.e);
			return (ABORT, nil);
		}
	}

	n := len f.bufout;
	if(n > len buf)
		n = len buf;
	buf[:] = f.bufout[:n];
	f.bufout = f.bufout[n:];
	if(t.vflag) info(t, sprint("returning result from filter n=%d i=%d name=%q", n, f.i, f.name));
	return (n, nil);
}

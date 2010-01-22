implement Filtrate;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
include "filter.m";
	filter: Filter;

Filtrate: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};


dflag := 0;
tab := array[] of {
	("deflate", Filter->DEFLATEPATH),
	("inflate", Filter->INFLATEPATH),
	("pdfinflate", "pdfinflate.dis"),
	("slip", Filter->SLIPPATH),
	("cascade", "cascadefilter.dis"),
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;

	params := "";

	arg->init(args);
	arg->setusage(arg->progname()+" [-d] [-p params] [file.dis | name]");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
		'p' =>	params = arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();

	name := hd args;
	file: string;
	if(len name > len ".dis" && name[len name-len".dis":] != ".dis") {
		for(i := 0; i < len tab; i++)
			if(tab[i].t0 == name) {
				file = tab[i].t1;
				break;
			}
		if(file == nil)
			fail(sprint("module not known: %q", name));
	} else
		file = name;
	filter = load Filter file;
	if(filter == nil)
		fail(sprint("loading %q: %r", file));
	filter->init();
	rq := filter->start(params);
done:
	for(;;) {
		pick m := <-rq {
		Start =>
			say(sprint("pid=%d", m.pid));
		Fill =>
			n := sys->read(sys->fildes(0), m.buf, len m.buf);
			if(n < 0)
				n = -1;
			say(sprint("fill, len m.buf %d, giving %d", len m.buf, n));
			m.reply <-= n;
			if(n < 0)
				fail(sprint("reading: %r"));
		Result =>
			say(sprint("result, len m.buf %d", len m.buf));
			n := sys->write(sys->fildes(1), m.buf, len m.buf);
			if(n != len m.buf)
				fail(sprint("writing: %r"));
			m.reply <-= 0;
		Finished =>
			say(sprint("finished, remaining %d bytes", len m.buf));
			break done;
		Info =>
			say("info: "+m.msg);
		Error =>
			fail("error: "+m.e);
		}
	}
	say("done");
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

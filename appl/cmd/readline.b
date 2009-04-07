implement Readline;

include "sys.m";
	sys: Sys;
include "draw.m";

Readline: module {
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	for(;;) {
		n := sys->read(sys->fildes(0), buf := array[1] of byte, len buf);
		if(n == 0)
			return;
		if(n < 0)
			fail("reading");
		if(sys->write(sys->fildes(1), buf, len buf) < 0)
			fail("writing");
		if(buf[0] == byte '\n')
			return;
	}
}

fail(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	raise "fail:"+s;
}

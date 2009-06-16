#
# regtest of pub3 filters
#

test_str = "AbCdE FghIJKlmNOpQr FfooXx CCCccattTTtT DDogg"

filedata ="""
{$ setl { x : "%s" } $}
{$ setl { lcx : x | tolower,
          ucx : x | tolower | toupper ,
          z = "     a-floater    " } $}

{$ setl { input : "abcdefgh" } $}

orig: ${x}
lowered: ${lcx}
lowered (encore): ${x|tolower}
lowered (encore II): ${"%s"|tolower}
lowered-then-uppered: ${ucx}

html filtration: ${"<bad> stuff & more <crap>"|html_escape}
json filtration: ${"\\n\\t\\\\"|json_escape}
substring(0): ${input|substr(2,4)}
substring(1): ${substr(input,2,4)}
substring(2): ${substr(input,0,3)}
substring(3): ${input|substr(0,3)}
strip-test: X---${z|strip()}---Y
empty json filtration: ${undef|json_escape}
""" % (test_str, test_str)

desc = "a test for filters"

outcome = """
orig: %s
lowered: %s
lowered (encore): %s
lowered (encore II): %s
lowered-then-uppered: %s

html filtration: &lt;bad&gt; stuff &#38; more &lt;crap&gt;
json filtration: "\\n\\t\\\\"
substring(0): cdef
substring(1): cdef
substring(2): abc
substring(3): abc
strip-test: X---a-floater---Y
empty json filtration: ""
""" % (test_str, test_str.lower (), test_str.lower (),  test_str.lower (),
       test_str.upper ())

// -*-c++-*-
/* $Id: ok.h 1967 2006-06-01 12:51:17Z max $ */

/*
 *
 * Copyright (C) 2002-2004 Maxwell Krohn (max@okcupid.com)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
 * USA
 *
 */

#ifndef _LIBAOK_OKXMLSRV_H
#define _LIBAOK_OKXMLSRV_H

# include "ok.h"
# include "okxmlparse.h"
# include "okxmlobj.h"

# ifdef HAVE_EXPAT


class okclnt_xmlrpc_base_t : public okclnt_base_t {
public:
  okclnt_xmlrpc_base_t (ptr<ahttpcon> xx, oksrvc_t *s, u_int to = 0)
    : okclnt_base_t (xx, s), _parser (xx, to) {}

  ~okclnt_xmlrpc_base_t () {}
  void parse (cbi cb) { _parser.parse (cb); }

  /*
   * A smattering of method to access data members of the underlying parser
   * object 
   */
  http_inhdr_t *hdr_p () { return _parser.hdr_p (); }
  const http_inhdr_t &hdr_cr () const { return _parser.hdr_cr (); }
  str errmsg () const { return _parser.errmsg (); }
  int errcode () const { return _parser.errcode (); }
  cgi_t &cookie () { return _parser.get_cookie (); }
  cgi_t &url () { return _parser.get_url (); }
  http_inhdr_t &hdr () { return _parser.hdr; }


  ptr<xml_top_level_t> top_level () { return _parser.top_level (); }
  ptr<const xml_top_level_t> top_level_const () const 
  { return _parser.top_level_const (); }

  void reply (xml_resp_t r);
protected:
  http_parser_xml_t _parser;
};

class oksrvc_xmlrpc_base_t : public oksrvc_t {
public:
  oksrvc_xmlrpc_base_t (int argc, char *argv[]) : oksrvc_t (argc, argv) {}
  virtual ~oksrvc_xmlrpc_base_t () {}
  virtual void handle (okclnt_xmlrpc_base_t *b) = 0;
};

class okclnt_xmlrpc_t : public okclnt_xmlrpc_base_t {
public:
  okclnt_xmlrpc_t (ptr<ahttpcon> xx, oksrvc_xmlrpc_base_t *s, u_int to = 0)
    : okclnt_xmlrpc_base_t (xx, s, to), _srvc (s) {}
  void process () { _srvc->handle (this); }
protected:
  oksrvc_xmlrpc_base_t *_srvc;
};

// See additional codes in "libokxml/okxmlparse.h" and <expat.h>
enum { OK_XMLRPC_OK = 0,
       OK_XMLRPC_ERR_NO_DATA = 101,
       OK_XMLRPC_ERR_NO_METHOD_CALL = 102,
       OK_XMLRPC_ERR_NO_METHOD_NAME = 103,
       OK_XMLRPC_ERR_METHOD_NOT_FOUND = 104 };

template<class C, class S>
class oksrvc_xmlrpc_t : public oksrvc_xmlrpc_base_t {
public:
  typedef void (C::*handler_t) (xml_req_t);

  oksrvc_xmlrpc_t (int argc, char *argv[]) 
    : oksrvc_xmlrpc_base_t (argc, argv) {}

  void handle (okclnt_xmlrpc_base_t *c)
  {
    xml_resp_t resp;
    bool handled = false;
    ptr<const xml_method_call_t> call;
    ptr<const xml_top_level_t> e;
    handler_t *h;
    str nm;

    C *cli = reinterpret_cast<C *> (c);

    zbuf z;
    if (c->top_level_const ()) {
      c->top_level_const ()->dump (z);
      strbuf b;
      z.to_strbuf (&b, false);
      b.tosuio ()->output (2);
    }

    if (c->errcode () != XML_PARSE_OK) {
      resp = xml_fault_obj_t (c->errcode (), c->errmsg ());
    } else if (!(e = c->top_level_const ()) || e->size () < 1) {
      resp = xml_fault_obj_t (OK_XMLRPC_ERR_NO_DATA, 
			      "No data given in XML call");
    } else if (!(call = e->get (0)->to_xml_method_call ())) {
      resp = xml_fault_obj_t (OK_XMLRPC_ERR_NO_METHOD_CALL, 
			      "No methodCall given in request");
    } else if (!(nm = call->method_name ())) {
      resp = xml_fault_obj_t (OK_XMLRPC_ERR_NO_METHOD_NAME,
			      "No method name given");
    } else if (!(h = _dispatch_table[nm])) {
      resp = xml_fault_obj_t (OK_XMLRPC_ERR_METHOD_NOT_FOUND, 
			      "Method not found");
    } else {
      handled = true;
      ((*cli).*(*h)) (xml_req_t (call->params_const ()));
    }

    if (!handled)
      c->reply (resp);
  }

  okclnt_base_t *make_newclnt (ptr<ahttpcon> lx) 
  { return New C (lx, reinterpret_cast<S *> (this)); }

protected:
  // register a handler
  void regh (const str &s, handler_t h) { _dispatch_table.insert (s, h); }
  void regh (const char *s, handler_t h) 
  { _dispatch_table.insert (str (s), h); }
private:
  qhash<str, handler_t> _dispatch_table;
};

# endif /* HAVE_EXPAT */
#endif /* _LIBAOK_OKXMLSRV_H */
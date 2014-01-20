import string

###############################################################################
# Simple Lisp s-expression parser
###############################################################################

# Possible error codes
PARSERR_NOSTARTBRACE        = -1    # s-expression does not start with a '('
PARSERR_NOCLOSEBRACE        = -2    # s-expression does not end with a '('
PARSERR_NOCLOSESTRING       = -3    # string is not closed with double quote
PARSERR_MISSINGLITERAL      = -4    # literal is missing after the escape character
PARSERR_EMPTY               = -5    # s-expression is empty


def parse_comment( sexpr ):
    """Parses a ';' Lisp comment till the end of line, returns comment length
    """
    pos = sexpr.find( '\n' )
    if pos >= 0:
        return pos + 1
    return len( sexpr )

def parse_keyword( sexpr ):
    """Parses a Lisp keyword, returns keyword length
    """
    for pos in range( len( sexpr ) ):
        if sexpr[pos] in string.whitespace + ')]':
            return pos
    return pos

def parse_sub_sexpr( sexpr, opening, closing ):
    """Parses a Lisp sub -expression, returns parsed string length
       and a Python list built from the s-expression,
       expression can be a Clojure style list surrounded by braces
    """
    result = []
    l = len( sexpr )
    for pos in range( l ):
        # Find first opening '(' or '['
        if sexpr[pos] == opening:
            break
        if not sexpr[pos] in string.whitespace:
            # S-expression does not start with '(' or '['
            return [PARSERR_NOSTARTBRACE, result]
    else:
        # Empty s-expression
        return [PARSERR_EMPTY, result]

    pos = pos + 1
    quote_cnt = 0
    while pos < l:
        literal = 0
        if sexpr[pos] == '\\':
            literal = 1
            pos = pos + 1
            if pos == l:
                return [PARSERR_MISSINGLITERAL, result]
        if not literal and sexpr[pos] == '"':
            # We toggle a string
            quote_cnt = 1 - quote_cnt
            if quote_cnt == 1:
                quote_pos = pos
            else:
                result = result + [sexpr[quote_pos:pos+1]]
        elif quote_cnt == 0:
            # We are not in a string
            if not literal and sexpr[pos] == '(':
                # Parse sub expression
                [slen, subresult] = parse_sub_sexpr( sexpr[pos:], '(', ')' )
                if slen < 0:
                    # Sub expression parsing error
                    return [slen, result]
                result = result + [subresult]
                pos = pos + slen - 1
            elif not literal and sexpr[pos] == '[':
                # Parse sub expression
                [slen, subresult] = parse_sub_sexpr( sexpr[pos:], '[', ']' )
                if slen < 0:
                    # Sub expression parsing error
                    return [slen, result]
                result = result + [subresult]
                pos = pos + slen - 1
            elif not literal and sexpr[pos] == closing:
                # End of this sub expression
                return [pos + 1, result]
            elif not literal and sexpr[pos] != closing and sexpr[pos] in ')]':
                # Wrong closing brace/bracket
                return [PARSERR_NOCLOSEBRACE, result]
            elif not literal and sexpr[pos] == ';':
                # Skip coment
                pos = pos + parse_comment( sexpr[pos:] ) - 1
            elif not literal and sexpr[pos] in "#'`@~,^":
                # Skip prefix characters
                while pos+1 < l and sexpr[pos+1] not in string.whitespace + '([':
                    pos = pos + 1
            elif not sexpr[pos] in string.whitespace + '\\':
                # Parse keyword but ignore dot in dotted notation (a . b)
                klen = parse_keyword( sexpr[pos:] )
                if klen > 1 or sexpr[pos] != '.':
                    result = result + [sexpr[pos:pos+klen]]
                    pos = pos + klen - 1
        pos = pos + 1

    if quote_cnt != 0:
        # Last string is not closed
        return [PARSERR_NOCLOSESTRING, result]
    # Closing ')' or ']' not found
    return [PARSERR_NOCLOSEBRACE, result]

def parse_sexpr( sexpr ):
    """Parses a Lisp s-expression, returns parsed string length
       and a Python list built from the s-expression
    """
    return parse_sub_sexpr( sexpr, '(', ')' )


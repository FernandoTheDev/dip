module main;

import std.exception;
import std.stdio;
import std.format;
import std.conv;
import std.path;
import std.file;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : memcpy;
import runtime;
import core.sys.posix.dlfcn;
import std.getopt;
import std.string;
import hm;

/**************
* ERROR REPORTER
*/

/**************
* LEXER
*/

enum TokenKind : ubyte
{
    ProgramHeader, // <?php

    // keywords
    Function,
    Return,
    Echo,
    If,
    Else,
    While,
    For,
    Do,
    Require,
    RequireOnce,
    Include,
    IncludeOnce,

    // Pragma
    PFFI,
    PBUILTIN,
    PEXTERN,

    // Literal
    String,
    Int,
    Float,

    Identifier, // hello
    DIdentifier, // $hello

    // symbols
    LParen, // (
    RParen, // )

    SemiColon, // ;

    LBrace, // {
    RBrace, // }

    Equals, // =

    PlusPlus, // ++
    MinusMinus, // --
    // six sevennnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn

    // 69 ;)
    Plus, // +
    Minus, // -
    Star, // *
    Slash, // /
    Modulo, // %

    Colon, // :
    Comma, // ,
    Dot, // .
    Question, // ?
    Pipe, // |
    Variadic, // ...

    LBracket, // [
    RBracket, // ]

    Tilde, // ~
    Bang, // !
    EEquals, // ==
    EEEquals, // ===
    NEquals, // !=
    Less, // <
    Greater, // >
    LessEq, // <=
    GreaterEq, // >=

    Eof, // \0
}

union TokenValue
{
    long num;
    double flt;
    string str;
    bool bol;
}

struct LinePosition
{
    uint offset, line;
}

struct Position
{
    LinePosition start;
    LinePosition end;
}

struct Token
{
    TokenKind kind;
    TokenValue value;
    Position pos;
}

class Lexer
{
private:
    string source;
    uint line, offset, loffset;
    Token[] tokens;
public:
    this(string prog)
    {
        this.source = prog;
    }

    pragma(inline, true)
    bool isAlpha(char ch)
    {
        return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_';
    }

    pragma(inline, true)
    bool isNum(char ch)
    {
        return ch >= '0' && ch <= '9';
    }

    pragma(inline, true)
    bool isAlphaNum(char ch)
    {
        return isAlpha(ch) || isNum(ch);
    }

    pragma(inline, true)
    bool isWhite(char ch)
    {
        return ch == '\t' || ch == '\r' || ch == ' ';
    }

    pragma(inline, true)
    char next(bool next = false)
    {
        enforce(offset < source.length, "Error in 'next()'.");
        loffset++;
        return next ? source[++offset] : source[offset++];
    }

    pragma(inline, true)
    char peek()
    {
        enforce(offset < source.length, "Error in 'peek()'.");
        return source[offset];
    }

    pragma(inline, true)
    Position makePos(uint start, uint startLine)
    {
        return Position(LinePosition(start, startLine), LinePosition(loffset, line));
    }

    pragma(inline, true)
    Token makeStr(TokenKind kind, string value, uint start, uint startLine)
    {
        Token tk = Token(kind);
        tk.value.str = value;
        tk.pos = makePos(start, startLine);
        return tk;
    }

    pragma(inline, true)
    Token makeInt(long value, uint start, uint startLine)
    {
        Token tk = Token(TokenKind.Int);
        tk.value.num = value;
        tk.pos = makePos(start, startLine);
        return tk;
    }

    pragma(inline, true)
    Token makeFloat(double value, uint start, uint startLine)
    {
        Token tk = Token(TokenKind.Float);
        tk.value.flt = value;
        tk.pos = makePos(start, startLine);
        return tk;
    }

    pragma(inline, true)
    void pushToken(Token tk)
    {
        this.tokens ~= tk;
    }

    ref Token[] tokenizer()
    {
        while (offset < source.length)
        {
            char ch = next();
            if (isWhite(ch))
                continue;
            if (ch == '\n')
            {
                line++;
                loffset = 0;
                continue;
            }

            if (ch == '<')
                if ((offset + 3) < source.length)
                    if (source[offset] == '?' && source[offset + 1 .. 5] == "php")
                    {
                        offset += 4;
                        line++;
                        pushToken(Token(TokenKind.ProgramHeader));
                        continue;
                    }

            // numeric
            if (isNum(ch))
            {
                uint start = loffset - 1;
                uint sline = line;
                string buffer;
                buffer ~= ch;
                bool isDouble;
                while ((isNum(peek()) || peek() == '.' || peek() == '_') && offset < source.length)
                {
                    if (peek() == '.')
                    {
                        isDouble = true;
                        next();
                        buffer ~= '.';
                        continue;
                    }
                    if (peek() == '_')
                    {
                        next();
                        continue;
                    }
                    buffer ~= next();
                }
                // writeln("buffer: ", buffer);
                Token tk = isDouble ? makeFloat(to!double(buffer), start, sline) : makeInt(to!long(buffer), start,
                    sline);
                pushToken(tk);
                continue;
            }

            // string
            if (ch == '"')
            {
                uint start = loffset - 1;
                uint sline = line;
                string buffer;
                while (peek() != '"' && offset < source.length)
                {
                    char c = next();
                    if (c == '\\')
                    {
                        if (peek() == '"')
                        {
                            buffer ~= '\"';
                            next();
                            continue;
                        }
                        if (peek() == '\'')
                        {
                            buffer ~= "\\'";
                            next();
                            continue;
                        }
                        if (peek() == '\\')
                        {
                            buffer ~= '\\';
                            next();
                            continue;
                        }
                        if (peek() == 'n')
                        {
                            buffer ~= '\n';
                            next();
                            continue;
                        }
                        if (peek() == 't')
                        {
                            buffer ~= '\t';
                            next();
                            continue;
                        }
                        if (peek() == 'r')
                        {
                            buffer ~= '\r';
                            next();
                            continue;
                        }
                        if (peek() == '0')
                        {
                            buffer ~= '\0';
                            next();
                            continue;
                        }
                        // TODO: dar erro se não achar o escape
                    }
                    buffer ~= c;
                }
                if (peek() != '\"')
                {
                    // TODO: dar erro
                    writeln("An '\"' is expected after the string.");
                    continue;
                }
                offset++; // skip the '"'
                loffset++;
                pushToken(makeStr(TokenKind.String, buffer, start, sline));
                continue;
            }

            // identifier or didentifier
            if (isAlpha(ch) || ch == '$')
            {
                uint start = loffset - 1;
                uint sline = line;
                bool isDolar;
                if (ch == '$')
                {
                    isDolar = true;
                }
                string buffer;
                buffer ~= ch;

                while (isAlphaNum(peek()) && offset < source.length)
                    buffer ~= next();

                if (buffer == "function")
                {
                    pushToken(makeStr(TokenKind.Function, buffer, start, sline));
                    continue;
                }
                if (buffer == "return")
                {
                    pushToken(makeStr(TokenKind.Return, buffer, start, sline));
                    continue;
                }
                if (buffer == "echo")
                {
                    pushToken(makeStr(TokenKind.Echo, buffer, start, sline));
                    continue;
                }
                if (buffer == "if")
                {
                    pushToken(makeStr(TokenKind.If, buffer, start, sline));
                    continue;
                }
                if (buffer == "else")
                {
                    pushToken(makeStr(TokenKind.Else, buffer, start, sline));
                    continue;
                }
                if (buffer == "while")
                {
                    pushToken(makeStr(TokenKind.While, buffer, start, sline));
                    continue;
                }
                if (buffer == "do")
                {
                    pushToken(makeStr(TokenKind.Do, buffer, start, sline));
                    continue;
                }
                if (buffer == "for")
                {
                    pushToken(makeStr(TokenKind.For, buffer, start, sline));
                    continue;
                }
                if (buffer == "require")
                {
                    pushToken(makeStr(TokenKind.Require, buffer, start, sline));
                    continue;
                }
                if (buffer == "include")
                {
                    pushToken(makeStr(TokenKind.Include, buffer, start, sline));
                    continue;
                }
                if (buffer == "require_once")
                {
                    pushToken(makeStr(TokenKind.RequireOnce, buffer, start, sline));
                    continue;
                }
                if (buffer == "include_once")
                {
                    pushToken(makeStr(TokenKind.IncludeOnce, buffer, start, sline));
                    continue;
                }

                pushToken(makeStr(isDolar ? TokenKind.DIdentifier
                        : TokenKind.Identifier, buffer, start, sline));
                continue; // fallback
            }

            // symbols
            if (ch == '/')
            {
                if (peek() == '/')
                {
                    // comment
                    while (offset < source.length && ch != '\n')
                        ch = next();
                    continue;
                }
                pushToken(makeStr(TokenKind.Slash, "/", loffset - 1, line));
                continue;
            }

            if (ch == '#')
            {
                // pragma
                // #>ffi
                // #>builtin
                if (peek() == '>')
                {
                    next();
                    if (offset + 7 != source.length)
                    {
                        if (source[offset .. offset + 7] == "builtin")
                        {
                            pushToken(makeStr(TokenKind.PBUILTIN, "", loffset, line));
                            offset += 7;
                            loffset += 7;
                        }
                        else if (source[offset .. offset + 3] == "ffi")
                        {
                            pushToken(makeStr(TokenKind.PFFI, "", loffset, line));
                            offset += 3;
                            loffset += 3;
                        }
                        else if (source[offset .. offset + 6] == "extern")
                        {
                            pushToken(makeStr(TokenKind.PEXTERN, "", loffset, line));
                            offset += 6;
                            loffset += 6;
                        }
                        continue;
                    }
                }
                // comment
                while (offset < source.length && ch != '\n')
                    ch = next();
                continue;
            }

            if (ch == '=')
            {
                if (peek() == '=')
                {
                    next();
                    if (peek() == '=')
                    {
                        next();
                        pushToken(makeStr(TokenKind.EEEquals, "===", loffset - 3, line));
                    }
                    else
                        pushToken(makeStr(TokenKind.EEquals, "==", loffset - 2, line));
                    continue;
                }
                else
                    pushToken(makeStr(TokenKind.Equals, "=", loffset - 1, line));
                continue;
            }

            if (ch == '!')
            {
                pushToken(makeStr(TokenKind.Bang, "!", loffset - 1, line));
                continue;
            }
            if (ch == '>')
            {
                pushToken(makeStr(TokenKind.Greater, ">", loffset - 1, line));
                continue;
            }
            if (ch == '<')
            {
                pushToken(makeStr(TokenKind.Less, "<", loffset - 1, line));
                continue;
            }

            if (ch == '~')
            {
                pushToken(makeStr(TokenKind.Tilde, "~", loffset - 1, line));
                continue;
            }
            if (ch == '+')
            {
                pushToken(makeStr(TokenKind.Plus, "+", loffset - 1, line));
                continue;
            }
            if (ch == '-')
            {
                pushToken(makeStr(TokenKind.Minus, "-", loffset - 1, line));
                continue;
            }
            if (ch == '*')
            {
                pushToken(makeStr(TokenKind.Star, "*", loffset - 1, line));
                continue;
            }
            if (ch == '(')
            {
                pushToken(makeStr(TokenKind.LParen, "(", loffset - 1, line));
                continue;
            }
            if (ch == ')')
            {
                pushToken(makeStr(TokenKind.RParen, ")", loffset - 1, line));
                continue;
            }
            if (ch == '{')
            {
                pushToken(makeStr(TokenKind.LBrace, "{", loffset - 1, line));
                continue;
            }
            if (ch == '}')
            {
                pushToken(makeStr(TokenKind.RBrace, "}", loffset - 1, line));
                continue;
            }
            if (ch == ';')
            {
                pushToken(makeStr(TokenKind.SemiColon, ";", loffset - 1, line));
                continue;
            }
            if (ch == ':')
            {
                pushToken(makeStr(TokenKind.Colon, ":", loffset - 1, line));
                continue;
            }
            if (ch == ',')
            {
                pushToken(makeStr(TokenKind.Comma, ",", loffset - 1, line));
                continue;
            }
            if (ch == '[')
            {
                pushToken(makeStr(TokenKind.LBracket, "[", loffset - 1, line));
                continue;
            }
            if (ch == ']')
            {
                pushToken(makeStr(TokenKind.RBracket, "]", loffset - 1, line));
                continue;
            }
            if (ch == '%')
            {
                pushToken(makeStr(TokenKind.Modulo, "%", loffset - 1, line));
                continue;
            }
            if (ch == '.')
            {
                if (source[offset .. offset+2] == "..")
                {
                    offset += 2;
                    loffset += 2;
                    pushToken(makeStr(TokenKind.Variadic, "...", loffset - 1, line));
                }
                else
                    pushToken(makeStr(TokenKind.Dot, ".", loffset - 1, line));
                continue;
            }
            if (ch == '?')
            {
                pushToken(makeStr(TokenKind.Question, "?", loffset - 1, line));
                continue;
            }
            if (ch == '|')
            {
                pushToken(makeStr(TokenKind.Pipe, "|", loffset - 1, line));
                continue;
            }

            // error
            writefln("Unknown character '%c'.", ch);
        }
        pushToken(Token(TokenKind.Eof));
        return tokens;
    }
}

/**************
* TYPES
*/

// enum Type {
//     Int,
//     Float,
//     Bool,
//     Array,
//     Mixed,
//     Callable,
//     Class,
//     Enum,
//     UserDefined,
// }

/**************
* PARSER
*/

// NODES

enum NodeKind : ubyte
{
    Program,
    AssignDecl,
    IntLit,
    FloatLit,
    Identifier,
    StringLit,
    DIdentifier,
    BinaryExpr,
    EchoStmt,
    IfStmt,
    BlockStmt,
    WhileStmt,
    FuncDecl,
    CallExpr,
    ReturnStmt,
    // TODO:
    ClassDecl,
    ArrayLit,
    SwitchStmt,
    ForStmt,
    ForEachStmt,
    RequireStmt, // require and require_once
    IncludeStmt, // include and include_once
}

struct Program
{
    Node[] body;
}

struct AssignDecl
{
    Node* target, value; // $x = 10
}

struct Identifier
{
    string value; // x
}

struct DIdentifier
{
    string value; // $x
}

struct IntLit
{
    long value;
}

struct FloatLit
{
    double value;
}

struct StringLit
{
    const(char)[] value;
}

struct BinaryExpr
{
    Node* right, left;
    string op; // +, +=, /=, ...
}

struct EchoStmt
{
    Node* value;
}

struct IfStmt
{
    Node* condition;
    Node* body;
    Node* elseBody;
}

struct BlockStmt
{
    Node[] body;
}

struct FnArgument
{
    Token arg;
    Node* dValue;
    uint idx;
}

struct FnDecl
{
    string name;
    FnArgument[] arguments;
    Node* body;
    bool isFFI;
    bool isBuiltin;
    bool isExtern;
}

struct WhileStmt
{
    Node* cond;
    Node* body;
}

struct ReturnStmt
{
    Node* value;
}

struct CallExpr
{
    string name;
    FnArgument[] arguments;
}

struct Node
{
    NodeKind kind;
    Position pos;
    union
    {
        Program program;
        AssignDecl assignDecl;
        BinaryExpr binaryExpr;
        Identifier identifier;
        DIdentifier didentifier;
        IntLit intLit;
        FloatLit floatLit;
        StringLit strLit;
        EchoStmt echo;
        BlockStmt block;
        IfStmt ifStmt;
        WhileStmt whileStmt;
        FnDecl fn;
        ReturnStmt returnStmt;
        CallExpr call;
    }
}

// PARSER

enum Precedence : ubyte
{
    Low,
    Assign, // =, +=, ...
    Sum, // +, -
    Mul, // *, /, %
    Call, // ms()
    Highest = 69,
}

struct ParseStatement
{
    Parser* parser;

    this(Parser* p)
    {
        this.parser = p;
    }

    Node* parse()
    {
        Token tk = parser.advance();
        switch (tk.kind)
        {
        case TokenKind.If:
            return parseIfStmt();
        case TokenKind.While:
            return parseWhileStmt();
        case TokenKind.LBrace:
            Node* n = new Node();
            n.kind = NodeKind.BlockStmt;
            while (!parser.check(TokenKind.RBrace) && !parser.isAtEnd())
            {
                n.block.body ~= *parser.parse();
                if (parser.match([TokenKind.SemiColon]))
                    continue;
            }
            enforce(parser.match([TokenKind.RBrace]), "Expected '}' after the block statement.");
            return n;
        case TokenKind.Echo:
            Node* n = new Node();
            n.kind = NodeKind.EchoStmt;
            n.echo.value = parser.expr.parse();
            return n;
        case TokenKind.Return:
            Node* n = new Node();
            n.kind = NodeKind.ReturnStmt;
            if (!parser.match([TokenKind.SemiColon]))
                n.returnStmt.value = parser.expr.parse();
            return n;
        default:
            return null;
        }
    }

    Node* parseWhileStmt()
    {
        enforce(parser.match([TokenKind.LParen]), "Expected '(' after 'while'.");
        Node* cond = parser.expr.parse();
        enforce(parser.match([TokenKind.RParen]), "Expected ')' after the expression.");
        Node* body = parser.check(TokenKind.LBrace) ? parse() : parser.parse();
        Node* n = new Node();
        n.kind = NodeKind.WhileStmt;
        n.whileStmt.cond = cond;
        n.whileStmt.body = body;
        return n;
    }

    Node* parseIfStmt()
    {
        enforce(parser.match([TokenKind.LParen]), "Expected '(' after 'if'.");
        Node* cond = parser.expr.parse();
        enforce(parser.match([TokenKind.RParen]), "Expected ')' after the expression.");
        Node* body = parser.check(TokenKind.LBrace) ? parse() : parser.parse();
        Node* elseBody = null;
        parser.match([TokenKind.SemiColon]);
        if (parser.match([TokenKind.Else]))
            elseBody = parser.peek().kind == TokenKind.LBrace ? parse() : parser.parse();
        Node* n = new Node();
        n.kind = NodeKind.IfStmt;
        n.ifStmt.condition = cond;
        n.ifStmt.body = body;
        n.ifStmt.elseBody = elseBody;
        return n;
    }
}

struct ParseDecl
{
    Parser* parser;

    this(Parser* p)
    {
        this.parser = p;
    }

    Node* parse()
    {
        Token tk = parser.advance();
        switch (tk.kind)
        {
        case TokenKind.Function:
            return parseFnDecl();
        default:
            return null;
        }
    }

    void ignoreTypes()
    {
        // ?int
        parser.match([TokenKind.Question, TokenKind.Identifier]);
        // ?int | ... | ...
        while (parser.match([TokenKind.Pipe]))
            parser.match([TokenKind.Question, TokenKind.Identifier]);
    }

    Node* parseFnDecl()
    {
        Token name = parser.consume(TokenKind.Identifier, "Expected an identifier to function name.");
        FnArgument[] arguments;
        parser.consume(TokenKind.LParen, "Expected '(' after function name.");
        uint idx;
        while (!parser.check(TokenKind.RParen) && !parser.isAtEnd())
        {
            ignoreTypes();
            parser.match([TokenKind.Variadic]);
            Node* value = null;
            Token argName = parser.consume(TokenKind.DIdentifier, "Expected an name for argument name.");
            arguments ~= FnArgument(argName, value, idx);
            if (parser.match([TokenKind.Equals]))
                value = parser.expr.parse();
            if (!parser.check(TokenKind.RParen))
                parser.consume(TokenKind.Comma, "Expected ',' after argument.");
            idx++;
        }
        parser.consume(TokenKind.RParen, "Expected ')' after arguments.");
        if (parser.match([TokenKind.Colon]))
            ignoreTypes();
        Node* n = new Node();
        n.kind = NodeKind.FuncDecl;
        n.fn.name = name.value.str;
        n.fn.arguments = arguments;
        n.fn.body = parser.stmt.parse();
        n.fn.isBuiltin = parser.pragmaBUILTIN;
        n.fn.isFFI = parser.pragmaFFI;
        n.fn.isExtern = parser.pragmaEXTERN;
        parser.resetPragma();
        return n;
    }
}

struct ParseExpression
{
    Parser* parser;

    this(Parser* p)
    {
        this.parser = p;
    }

    Node* parse(ubyte level = Precedence.Low)
    {
        Node* left = expression();
        while (peekPrecedence(parser.peek()) > level)
            left = infix(left);
        return left;
    }

    Node* expression()
    {
        Token tk = parser.advance();
        switch (tk.kind)
        {
        case TokenKind.DIdentifier:
            Node* n = new Node();
            n.kind = NodeKind.DIdentifier;
            n.didentifier.value = tk.value.str;
            return n;
        case TokenKind.Identifier:
            Node* n = new Node();
            n.kind = NodeKind.Identifier;
            n.identifier.value = tk.value.str;
            return n;
        case TokenKind.Int:
            Node* n = new Node();
            n.kind = NodeKind.IntLit;
            n.intLit.value = tk.value.num;
            return n;
        case TokenKind.Float:
            Node* n = new Node();
            n.kind = NodeKind.FloatLit;
            n.floatLit.value = tk.value.flt;
            return n;
        case TokenKind.String:
            Node* n = new Node();
            n.kind = NodeKind.StringLit;
            n.strLit.value = tk.value.str;
            return n;
        case TokenKind.LParen:
            Node* n = parse();
            enforce(parser.match([TokenKind.RParen]), "Expected ')' after expr.");
            return n;
            break;
        default:
            writeln(tk);
            throw new Exception("Unknown token.");
        }
    }

    Node* binaryExpr(Node* left)
    {
        ubyte level = peekPrecedence(parser.peek());
        string op = parser.advance().value.str;
        Node* n = new Node();
        n.kind = NodeKind.BinaryExpr;
        n.binaryExpr.left = left;
        n.binaryExpr.right = parse(level);
        n.binaryExpr.op = op;
        return n;
    }

    Node* assignDecl(Node* left)
    {
        parser.advance();
        Node* n = new Node();
        n.kind = NodeKind.AssignDecl;
        n.assignDecl.target = left;
        n.assignDecl.value = parse();
        return n;
    }

    Node* callExpr(Node* left)
    {
        FnArgument[] arguments;
        parser.consume(TokenKind.LParen, "Expected '(' after function name in call.");
        uint idx;
        while (!parser.check(TokenKind.RParen) && !parser.isAtEnd())
        {
            Token argName;
            Node* value = parser.expr.parse();
            arguments ~= FnArgument(argName, value, idx);
            if (!parser.check(TokenKind.RParen))
                parser.consume(TokenKind.Comma, "Expected ',' after argument.");
            idx++;
        }
        parser.consume(TokenKind.RParen, "Expected ')' after arguments in call.");
        Node* n = new Node();
        n.kind = NodeKind.CallExpr;
        n.call.name = left.identifier.value;
        n.call.arguments = arguments;
        return n;
    }

    Node* infix(Node* left)
    {
        switch (parser.peek().kind)
        {
        case TokenKind.Plus:
        case TokenKind.Minus:
        case TokenKind.Star:
        case TokenKind.Slash:
        case TokenKind.Modulo:
        case TokenKind.Greater:
        case TokenKind.GreaterEq:
        case TokenKind.Less:
        case TokenKind.LessEq:
        case TokenKind.EEEquals:
        case TokenKind.EEquals:
            return binaryExpr(left);
        case TokenKind.Equals:
            return assignDecl(left);
        case TokenKind.LParen:
            return callExpr(left);
        default:
            return left;
        }
    }

    ubyte peekPrecedence(Token tk)
    {
        switch (tk.kind)
        {
        case TokenKind.Plus:
        case TokenKind.Minus:
            return Precedence.Sum;
        case TokenKind.Star:
        case TokenKind.Slash:
        case TokenKind.Modulo:
        case TokenKind.Greater:
        case TokenKind.GreaterEq:
        case TokenKind.Less:
        case TokenKind.LessEq:
        case TokenKind.EEEquals:
        case TokenKind.EEquals:
            return Precedence.Mul;
        case TokenKind.Equals:
            return Precedence.Assign;
        case TokenKind.LParen:
            return Precedence.Call;
        default:
            return Precedence.Low;
        }
    }
}

struct Parser
{
    uint offset;
    Token[] tokens;
    ParseDecl decl;
    ParseExpression expr;
    ParseStatement stmt;
    bool pragmaFFI;
    bool pragmaBUILTIN;
    bool pragmaEXTERN;

    void setup()
    {
        this.decl = ParseDecl(&this);
        this.expr = ParseExpression(&this);
        this.stmt = ParseStatement(&this);
    }

    @disable this(this); // desabilita cópias por segurança

    Node* parse()
    {
        if (peek().kind == TokenKind.SemiColon)
        {
            offset++;
            return parse();
        }
        if (peek().kind == TokenKind.Eof)
        {
            offset++;
            return null;
        }
        if (isDecl())
            return decl.parse();
        if (isStmt())
            return stmt.parse();
        return expr.parse();
    }

    Node parseProgram()
    {
        enforce(tokens[offset].kind == TokenKind.ProgramHeader, "The program is invalid.");
        offset++;
        Node p = Node();
        p.kind = NodeKind.Program;
        Node[] nodes;
        while (offset < tokens.length)
        {
            if (peek().kind == TokenKind.PBUILTIN)
            {
                offset++;
                pragmaBUILTIN = true;
                continue;
            }
            if (peek().kind == TokenKind.PFFI)
            {
                offset++;
                pragmaFFI = true;
                continue;
            }
            if (peek().kind == TokenKind.PEXTERN)
            {
                offset++;
                pragmaEXTERN = true;
                continue;
            }
            Node* n = parse();
            if (n !is null)
                nodes ~= *n;
            else
                offset++;
        }
        p.program.body = nodes;
        return p;
    }

    void resetPragma()
    {
        pragmaBUILTIN = false;
        pragmaFFI = false;
        pragmaEXTERN = false;
    }

    bool isDecl()
    {
        switch (peek().kind)
        {
        case TokenKind.Function:
            return true;
        default:
            return false;
        }
    }

    bool isStmt()
    {
        switch (peek().kind)
        {
        case TokenKind.LBrace:
        case TokenKind.If:
        case TokenKind.Echo:
        case TokenKind.Return:
        case TokenKind.While:
            return true;
        default:
            return false;
        }
    }

    pragma(inline, true)
    bool isAtEnd()
    {
        return (offset < tokens.length) == false || peek().kind == TokenKind.Eof;
    }

    pragma(inline, true)
    bool match(TokenKind[] kinds)
    {
        TokenKind p = peek().kind;
        foreach (TokenKind k; kinds)
            if (p == k)
            {
                offset++;
                return true;
            }
        return false;
    }

    pragma(inline, true)
    Token advance()
    {
        return isAtEnd() ? peek() : tokens[offset++];
    }

    pragma(inline, true)
    Token peek()
    {
        return tokens[offset];
    }

    pragma(inline, true)
    bool check(TokenKind kind)
    {
        return tokens[offset].kind == kind;
    }

    pragma(inline, true)
    Token consume(TokenKind kind, string msg)
    {
        if (this.check(kind))
            return this.advance();
        throw new Exception(format("Parsing error: %s", msg));
    }
}

/**************
* COMPILER (AST->BYTECODE)
*/

uint encode_abc(ubyte opcode, ubyte a = 0, ubyte b = 0, ubyte c = 0)
{
    return opcode | (a << 8) | (b << 16) | (c << 24);
}

uint encode_a(ubyte opcode, ushort a = 0)
{
    return opcode | (a << 8);
}

struct Label
{
    string name;
    uint address;
    uint[] patches;
}

struct Compiler
{
    Node* program;
    uint[] instructions;
    HVMValue* pool;
    uint poolSz = 0;
    uint[string] stringCache;
    bool[string] ffiFunctions;

    Label[string] labels;
    string label = "main"; // current label
    uint labelCounter;

    this(Node* program)
    {
        this.program = program;
        this.pool = cast(HVMValue*) malloc(HVMValue.sizeof * 64);
    }

    pragma(inline, true);
    void push(uint u)
    {
        this.instructions ~= u;
    }

    pragma(inline, true);
    string makeLabel(string prefix = "L")
    {
        return format("%s.%s.%d", label, prefix, labelCounter++);
    }

    pragma(inline, true);
    void defineLabel(string name)
    {
        if (name in labels)
        {
            labels[name].address = cast(uint) instructions.length;
            foreach (patchAddr; labels[name].patches)
                patchAddress(patchAddr, labels[name].address);
            labels[name].patches = [];
        }
        else
            labels[name] = Label(name, cast(uint) instructions.length, []);
    }

    pragma(inline, true);
    void emitJump(ubyte opcode, string targetLabel)
    {
        uint instrIdx = cast(uint) instructions.length;
        if (targetLabel in labels && labels[targetLabel].address != 0xFFFFFFFF) // Label já foi definida (backward jump)
            push(encode_a(opcode, cast(ushort) labels[targetLabel].address));
        else
        {
            // Label ainda não existe (forward jump)
            push(encode_a(opcode, 0)); // Placeholder    
            // Registra para patch futuro
            if (targetLabel !in labels)
                labels[targetLabel] = Label(targetLabel, 0xFFFFFFFF, []);
            labels[targetLabel].patches ~= instrIdx;
        }
    }

    pragma(inline, true);
    void patchAddress(uint instrIdx, uint targetAddr)
    {
        ubyte opcode = cast(ubyte)(instructions[instrIdx] & 0xFF);
        instructions[instrIdx] = encode_a(opcode, cast(ushort) targetAddr);
    }

    ushort internString(const(char)[] str)
    {
        string key = str.idup;

        if (auto idx = key in stringCache)
            return cast(ushort)*idx;

        ushort idx = cast(ushort) poolSz;
        char* strCopy = cast(char*) malloc(str.length + 1);
        memcpy(strCopy, str.ptr, str.length);
        strCopy[str.length] = '\0';

        pool[poolSz++] = HVMValue.makeString(strCopy, cast(uint) str.length);
        stringCache[key] = idx;

        return idx;
    }

    void compileDIdentifier(Node* node)
    {
        ushort idx = internString(node.didentifier.value);
        push(encode_a(HVMOpCode.Loadk, idx));
        push(encode_a(HVMOpCode.Load));
    }

    void compileAssignDecl(Node* node)
    {
        compile(node.assignDecl.value);
        Node* target = node.assignDecl.target;

        ushort idx = internString(target.didentifier.value);
        push(encode_a(HVMOpCode.Loadk, idx));
        push(encode_abc(HVMOpCode.Store));
    }

    void compileIdentifier(Node* node)
    {
        writeln("Idx");
        writeln(node.identifier.value);
    }

    void compileIntLit(Node* node)
    {
        ushort idx = cast(ushort) poolSz;
        pool[poolSz++] = HVMValue.makeInt(node.intLit.value);
        push(encode_a(HVMOpCode.Loadk, idx));
    }

    void compileFloatLit(Node* node)
    {
        ushort idx = cast(ushort) poolSz;
        pool[poolSz++] = HVMValue.makeFloat(node.floatLit.value);
        push(encode_a(HVMOpCode.Loadk, idx));
    }

    void compileStrLit(Node* node)
    {
        ushort idx = internString(node.strLit.value);
        push(encode_a(HVMOpCode.Loadk, idx));
    }

    void compileBinaryExpr(Node* node)
    {
        string op = node.binaryExpr.op;
        compile(node.binaryExpr.right);
        compile(node.binaryExpr.left);
        ubyte opcode = HVMOpCode.Add;
        if (op == "+")
            opcode = HVMOpCode.Add;
        else if (op == "-")
            opcode = HVMOpCode.Sub;
        else if (op == "*")
            opcode = HVMOpCode.Mul;
        else if (op == "/")
            opcode = HVMOpCode.Div;
        else if (op == "%")
            opcode = HVMOpCode.Mod;
        else if (op == "==")
            opcode = HVMOpCode.Eq;
        else if (op == "<")
            opcode = HVMOpCode.Lt;
        push(encode_abc(opcode));
    }

    void compileEchoStmt(Node* node)
    {
        compile(node.echo.value);
        push(HVMOpCode.Echo);
    }

    void compileIfStmt(Node* node)
    {
        string elseLabel = makeLabel("else");
        string endLabel = makeLabel("end");

        compile(node.ifStmt.condition);

        if (node.ifStmt.elseBody !is null)
            emitJump(HVMOpCode.Jz, elseLabel);
        else
            emitJump(HVMOpCode.Jz, endLabel);

        compile(node.ifStmt.body);

        if (node.ifStmt.elseBody !is null)
        {
            emitJump(HVMOpCode.Jmp, endLabel);
            defineLabel(elseLabel);
            compile(node.ifStmt.elseBody);
        }

        defineLabel(endLabel);
    }

    void compileBlockStmt(Node* node)
    {
        foreach (ref stmt; node.block.body)
            compile(&stmt);
    }

    void compileWhileStmt(Node* node)
    {
        string loopStart = makeLabel("loop");
        string endLabel = makeLabel("end");

        defineLabel(loopStart);
        compile(node.whileStmt.cond);

        emitJump(HVMOpCode.Jz, endLabel);
        compile(node.whileStmt.body);

        emitJump(HVMOpCode.Jmp, loopStart);
        defineLabel(endLabel);
    }

    void compileFnDecl(Node* node)
    {
        if (node.fn.isFFI || node.fn.isBuiltin || node.fn.isExtern)
        {
            if (node.fn.isFFI)
            {
                bool find;
                ffiFunctions[node.fn.name] = true;
                for (ubyte i; i < handlersSz; i++)
                {
                    FN_FFI fn = cast(FN_FFI) dlsym(HANDLERS[i], node.fn.name.toStringz);
                    if (fn is null) continue;
                    FFI_FUNCTIONS.put(node.fn.name, fn);
                    find = true;
                    break;
                }
                enforce(find == true, format("Symbol not found '%s'.", node.fn.name));
            }
            return;
        }

        string fnLabel = node.fn.name;
        string endLabel = makeLabel("fn_end");

        emitJump(HVMOpCode.Jmp, endLabel);
        defineLabel(fnLabel);

        foreach_reverse (arg; node.fn.arguments)
        {
            ushort idx = internString(arg.arg.value.str);
            push(encode_a(HVMOpCode.Loadk, idx));
            push(encode_abc(HVMOpCode.Store));
        }

        compile(node.fn.body);

        // Se não houver return explícito, retorna 0
        push(encode_a(HVMOpCode.Loadk, cast(ushort) poolSz));
        pool[poolSz++] = HVMValue.makeInt(0);
        push(encode_abc(HVMOpCode.Ret));

        defineLabel(endLabel);
    }

    void compileCallExpr(Node* node)
    {
        // Empilha os argumentos na ordem normal
        foreach (arg; node.call.arguments)
        {
            if (arg.dValue !is null)
                compile(arg.dValue);
            else
            {
                // Argumento é uma referência a variável
                ushort idx = internString(arg.arg.value.str);
                push(encode_a(HVMOpCode.Loadk, idx));
                push(encode_a(HVMOpCode.Load));
            }
        }

        string str = node.call.name;
        char* strCopy = cast(char*) malloc(str.length + 1);
        memcpy(strCopy, str.ptr, str.length);
        strCopy[str.length] = '\0';
        bool find1 = findBuiltin(strCopy) !is null;
        bool* find2 = str in ffiFunctions;

        if (!find1 && find2 is null)
            emitJump(HVMOpCode.Call, str);
        else
        {
            push(encode_a(HVMOpCode.Loadk, internString(str)));
            ubyte argc = cast(ubyte) node.call.arguments.length;
            ubyte op = HVMOpCode.Callf;
            if (find1)
                op = HVMOpCode.Callb;
            push(encode_a(op, argc));
        }

        free(strCopy);
    }

    void compileReturnStmt(Node* node)
    {
        if (node.returnStmt.value !is null)
            compile(node.returnStmt.value);
        else
        {
            // Return sem valor - empilha 0
            push(encode_a(HVMOpCode.Loadk, cast(ushort) poolSz));
            pool[poolSz++] = HVMValue.makeInt(0);
        }

        push(encode_abc(HVMOpCode.Ret));
    }

    void compile(Node* node)
    {
        switch (node.kind)
        {
        case NodeKind.AssignDecl:
            compileAssignDecl(node);
            break;
        case NodeKind.Identifier:
            compileIdentifier(node);
            break;
        case NodeKind.DIdentifier:
            compileDIdentifier(node);
            break;
        case NodeKind.IntLit:
            compileIntLit(node);
            break;
        case NodeKind.StringLit:
            compileStrLit(node);
            break;
        case NodeKind.FloatLit:
            compileFloatLit(node);
            break;
        case NodeKind.BinaryExpr:
            compileBinaryExpr(node);
            break;
        case NodeKind.EchoStmt:
            compileEchoStmt(node);
            break;
        case NodeKind.IfStmt:
            compileIfStmt(node);
            break;
        case NodeKind.BlockStmt:
            compileBlockStmt(node);
            break;
        case NodeKind.WhileStmt:
            compileWhileStmt(node);
            break;
        case NodeKind.FuncDecl:
            compileFnDecl(node);
            break;
        case NodeKind.ReturnStmt:
            compileReturnStmt(node);
            break;
        case NodeKind.CallExpr:
            compileCallExpr(node);
            break;
        default:
            writeln(node.kind);
            throw new Exception("Unknown node in compiler.");
            return;
        }
    }

    ref uint[] compile()
    {
        defineLabel("main");
        Node[] body = program.program.body;
        foreach (ref Node n; body)
            compile(&n);
        instructions ~= HVMOpCode.Hlt;

        foreach (name, label; labels)
            if (label.address == 0xFFFFFFFF && label.patches.length > 0)
                throw new Exception(format("Undefined label: %s", name));

        return instructions;
    }
}

/**************
* RUNTIME (VM)
*/

import vm;

/**************
* MAIN
*/

// FFI

const ubyte LIMIT1 = 16;
void*[LIMIT1] HANDLERS;
ubyte handlersSz = 0;
HashMap!(string, FN_FFI) FFI_FUNCTIONS;

// MAIN

void main(string[] args)
{
    try
    {
        string[] libs;
        getopt(args, "L|link", &libs); // dip -L test.so file.php

        // startup

        FFI_FUNCTIONS.initialize();
        foreach (string lib; libs)
        {
            void* handle = dlopen(lib.toStringz, RTLD_LAZY);
            if (handle is null)
            {
                writefln("Error on lib '%s': %s", lib, dlerror().fromStringz);
                return;
            }
            if (handlersSz == LIMIT1)
            {
                writeln("Limit error.");
                return;
            }
            HANDLERS[handlersSz++] = handle;
        }

        // ...

        enforce(args.length == 2, "The program expects a single argument to be presented.");
        string filename = args[1];
        enforce(extension(filename) == ".php", "A PHP file is expected as an argument.");
        enforce(exists(filename), format("The file '%s' does not exist.", filename));

        string source = readText(filename);
        Lexer lexer = new Lexer(source);
        Token[] tokens = lexer.tokenizer();

        Parser parser = Parser(0, tokens);
        parser.setup();
        Node program = parser.parseProgram();

        Compiler compiler = Compiler(&program);
        uint[] p = compiler.compile();
        uint* prog = cast(uint*) malloc(uint.sizeof * p.length);
        foreach (k, v; p)
            prog[k] = v;

        HVM* vm = HVM_create(prog, cast(uint) p.length, compiler.pool, compiler.poolSz, false);
        vm.run();
        free(vm);

        for (ubyte i; i < handlersSz; i++)
            dlclose(HANDLERS[i]);

        scope (exit)
            if (compiler.pool !is null)
                free(compiler.pool);
    }
    catch (Exception e)
    {
        writeln("Fatal error: ", e.msg);
        writeln("On File: ", e.file);
        writeln("On Line: ", e.line);
    }
}

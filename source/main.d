module main;

import std.exception;
import std.stdio;
import std.format;
import std.conv;
import std.path;
import std.file;

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
    Plus, // +
    PlusPlus, // ++
    Minus, // -
    MinusMinus, // --
    Star, // *
    Slash, // /
    Colon, // :
    Comma, // ,
    LBracket, // [
    RBracket, // ]

    Eof, // \0
}

union TokenValue {
    long num;
    double flt;
    string str;
    bool bol;
}

struct LinePosition {
    uint offset, line;
}

struct Position {
    LinePosition start;
    LinePosition end;
}

struct Token {
    TokenKind kind;
    TokenValue value;
    Position pos;
}

class Lexer {
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

    Token[] tokenizer()
    {
        while (offset < source.length)
        {
            char ch = next();
            if (isWhite(ch)) continue;
            if (ch == '\n') { line++; loffset = 0; continue; }
            // writeln(ch);

            if (ch == '<')
            {
                if ((offset + 3) < source.length)
                {
                    if (source[offset] == '?' && source[offset+1..5] == "php")
                    {
                        // writeln("HEADER");
                        offset += 4;
                        line++;
                        pushToken(Token(TokenKind.ProgramHeader));
                        continue;
                    }
                }
            }

            // numeric
            if (isNum(ch))
            {
                uint start = loffset-1;
                uint sline = line;
                string buffer;
                buffer ~= ch;
                bool isDouble;
                while (isNum(peek()) && offset < source.length)
                {
                    if (peek() == '.') { isDouble = true; next(); continue; }
                    if (peek() == '_') { next(); continue; }
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
                uint start = loffset-1;
                uint sline = line;
                string buffer;
                buffer ~= ch;
                while (peek() != '"' && offset < source.length)
                {
                    char c = next();
                    if (c == '\\')
                    {
                        if (peek() == '"') { buffer ~= '\"'; continue;}
                        if (peek() == '\'') { buffer ~= "\\'"; continue;}
                        if (peek() == '\\') { buffer ~= '\\'; continue;}
                        if (peek() == 'n') { buffer ~= '\n'; continue;}
                        if (peek() == 't') { buffer ~= '\t'; continue;}
                        if (peek() == 'r') { buffer ~= '\r'; continue;}
                        if (peek() == '0') { buffer ~= '\0'; continue;}
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
                // writeln("buffer: ", buffer);
                offset++; // skip the '"'
                loffset++;
                pushToken(makeStr(TokenKind.String, buffer, start, sline));
                continue;
            }

            // identifier or didentifier
            if (isAlpha(ch) || ch == '$')
            {
                uint start = loffset-1;
                uint sline = line;
                bool isDolar;
                if (ch == '$') { offset++; loffset++; isDolar = true; }
                string buffer;
                buffer ~= ch;
                // writeln("ID CHECK: ", isAlphaNum(peek()), " '", peek(), "'");
                while (isAlphaNum(peek()) && offset < source.length) 
                    buffer ~= next();
                // writefln("ID BUFFER: '%s'", buffer);
                if (buffer == "function") { pushToken(makeStr(TokenKind.Function, buffer, start, sline)); continue; }
                if (buffer == "return") { pushToken(makeStr(TokenKind.Return, buffer, start, sline)); continue; }
                if (buffer == "echo") { pushToken(makeStr(TokenKind.Echo, buffer, start, sline)); continue; }
                pushToken(makeStr(isDolar ? TokenKind.DIdentifier : TokenKind.Identifier, buffer, start, sline)); 
                continue; // fallback
            }

            // symbols
            if (ch == '+') { pushToken(makeStr(TokenKind.Plus,      "+", loffset-1, line)); continue; }
            if (ch == '-') { pushToken(makeStr(TokenKind.Minus,     "-", loffset-1, line)); continue; }
            if (ch == '=') { pushToken(makeStr(TokenKind.Equals,    "=", loffset-1, line)); continue; }
            if (ch == '/') { pushToken(makeStr(TokenKind.Slash,     "/", loffset-1, line)); continue; }
            if (ch == '*') { pushToken(makeStr(TokenKind.Star,      "*", loffset-1, line)); continue; }
            if (ch == '(') { pushToken(makeStr(TokenKind.LParen,    "(", loffset-1, line)); continue; }
            if (ch == ')') { pushToken(makeStr(TokenKind.RParen,    ")", loffset-1, line)); continue; }
            if (ch == '{') { pushToken(makeStr(TokenKind.LBrace,    "{", loffset-1, line)); continue; }
            if (ch == '}') { pushToken(makeStr(TokenKind.RBrace,    "}", loffset-1, line)); continue; }
            if (ch == ';') { pushToken(makeStr(TokenKind.SemiColon, ";", loffset-1, line)); continue; }
            if (ch == ':') { pushToken(makeStr(TokenKind.SemiColon, ":", loffset-1, line)); continue; }
            if (ch == ',') { pushToken(makeStr(TokenKind.SemiColon, ",", loffset-1, line)); continue; }
            if (ch == '[') { pushToken(makeStr(TokenKind.SemiColon, "[", loffset-1, line)); continue; }
            if (ch == ']') { pushToken(makeStr(TokenKind.SemiColon, "]", loffset-1, line)); continue; }

            // error
            writefln("Unknown character '%c'.", ch);
        }
        pushToken(Token(TokenKind.Eof));
        return tokens;
    }
}


/**************
* PARSER
*/

enum NodeKind : ubyte {
    // TODO:
    Program,
    AssignDecl,
    BinaryExpr,
    IntLit,
    Identifier,
    EchoStmt,
    FuncDecl,
    ClassDecl,
    FloatLit,
    StringLit,
    ArrayLit,
    BlockStmt,
    IfStmt,
    SwitchStmt,
    ForStmt,
    ForEachStmt,
    RequireStmt, // require and require_once
    IncludeStmt, // include and include_once
}

struct Program {
    Node[] body;
}

struct Node {
    NodeKind kind;
    union {
        Program program;
    }
}

struct ParseStatement {

}

struct ParseDecl {

}

struct ParseExpression {

}

struct Parser {

}


/**************
* RUNTIME (VM)
*/

/**************
* MAIN
*/

void main(string[] args)
{
    try 
    {
        enforce(args.length == 2, "The program expects a single argument to be presented.");
        string filename = args[1];
        enforce(extension(filename) == ".php", "A PHP file is expected as an argument.");
        enforce(exists(filename), format("The file '%s' does not exist.", filename));
        
        string source = readText(filename);
        Lexer lexer = new Lexer(source);
        Token[] tokens = lexer.tokenizer();
        
        writeln(tokens);
    } catch (Exception e)
    {
        writeln("Fatal error: ", e.msg);        
        writeln("On File: ", e.file);        
        writeln("On Line: ", e.line);        
    }
}

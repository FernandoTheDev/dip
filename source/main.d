module main;

import std.exception;
import std.stdio;
import std.format;
import std.conv;
import std.path;
import std.file;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : memcpy;

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
    
    Plus, // +
    Minus, // -
    Star, // *
    Slash, // /
    Modulo, // %
    
    Colon, // :
    Comma, // ,
    Dot, // .
    
    LBracket, // [
    RBracket, // ]
    
    Tilde, // ~
    // six seven
    Bang, // !
    // 69 ;)
    EEquals, // ==
    EEEquals, // ===
    NEquals, // !=
    Less, // <
    Greater, // >
    LessEq, // <=
    GreaterEq, // >=

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

    ref Token[] tokenizer()
    {
        while (offset < source.length)
        {
            char ch = next();
            if (isWhite(ch)) continue;
            if (ch == '\n') { line++; loffset = 0; continue; }
            
            if (ch == '<')
                if ((offset + 3) < source.length)
                    if (source[offset] == '?' && source[offset+1..5] == "php")
                    {
                        offset += 4;
                        line++;
                        pushToken(Token(TokenKind.ProgramHeader));
                        continue;
                    }
            
            // numeric
            if (isNum(ch))
            {
                uint start = loffset-1;
                uint sline = line;
                string buffer;
                buffer ~= ch;
                bool isDouble;
                while ((isNum(peek()) || peek() == '.' || peek() == '_') && offset < source.length)
                {
                    if (peek() == '.') { isDouble = true; next(); buffer ~= '.'; continue; }
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
                while (peek() != '"' && offset < source.length)
                {
                    char c = next();
                    if (c == '\\')
                    {
                        if (peek() == '"') { buffer ~= '\"'; next();   continue;}
                        if (peek() == '\'') { buffer ~= "\\'"; next(); continue;}
                        if (peek() == '\\') { buffer ~= '\\'; next();  continue;}
                        if (peek() == 'n') { buffer ~= '\n'; next();   continue;}
                        if (peek() == 't') { buffer ~= '\t'; next();   continue;}
                        if (peek() == 'r') { buffer ~= '\r'; next();   continue;}
                        if (peek() == '0') { buffer ~= '\0'; next();   continue;}
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
                uint start = loffset-1;
                uint sline = line;
                bool isDolar;
                if (ch == '$') { isDolar = true; }
                string buffer;
                buffer ~= ch;
                
                while (isAlphaNum(peek()) && offset < source.length) 
                    buffer ~= next();
                
                if (buffer == "function") { pushToken(makeStr(TokenKind.Function, buffer, start, sline)); continue; }
                if (buffer == "return")   { pushToken(makeStr(TokenKind.Return, buffer, start, sline)); continue; }
                if (buffer == "echo")     { pushToken(makeStr(TokenKind.Echo, buffer, start, sline)); continue; }
                if (buffer == "if")       { pushToken(makeStr(TokenKind.If, buffer, start, sline)); continue; }
                if (buffer == "else")     { pushToken(makeStr(TokenKind.Else, buffer, start, sline)); continue; }
                
                pushToken(makeStr(isDolar ? TokenKind.DIdentifier : TokenKind.Identifier, buffer, start, sline)); 
                continue; // fallback
            }

            // symbols
            if (ch == '/') { 
                if (peek() == '/')
                {
                    // comment
                    while (offset < source.length && ch != '\n') ch = next();
                    continue;
                }
                pushToken(makeStr(TokenKind.Slash,     "/", loffset-1, line)); 
                continue;
            }

            if (ch == '=') { 
                if (peek() == '=')
                {
                    next();
                    if (peek() == '=')
                    {
                        next();
                        pushToken(makeStr(TokenKind.EEEquals, "===", loffset-3, line));
                    }
                    else 
                        pushToken(makeStr(TokenKind.EEquals, "==", loffset-2, line)); 
                    continue;
                }
                else pushToken(makeStr(TokenKind.Equals, "=", loffset-1, line));
                continue; 
            }
            
            if (ch == '!') { pushToken(makeStr(TokenKind.Bang,      "!", loffset-1, line)); continue; }
            if (ch == '>') { pushToken(makeStr(TokenKind.Greater,   ">", loffset-1, line)); continue; }
            if (ch == '<') { pushToken(makeStr(TokenKind.Less,      "<", loffset-1, line)); continue; }
            
            if (ch == '~') { pushToken(makeStr(TokenKind.Tilde,     "~", loffset-1, line)); continue; }
            if (ch == '+') { pushToken(makeStr(TokenKind.Plus,      "+", loffset-1, line)); continue; }
            if (ch == '-') { pushToken(makeStr(TokenKind.Minus,     "-", loffset-1, line)); continue; }
            if (ch == '*') { pushToken(makeStr(TokenKind.Star,      "*", loffset-1, line)); continue; }
            if (ch == '(') { pushToken(makeStr(TokenKind.LParen,    "(", loffset-1, line)); continue; }
            if (ch == ')') { pushToken(makeStr(TokenKind.RParen,    ")", loffset-1, line)); continue; }
            if (ch == '{') { pushToken(makeStr(TokenKind.LBrace,    "{", loffset-1, line)); continue; }
            if (ch == '}') { pushToken(makeStr(TokenKind.RBrace,    "}", loffset-1, line)); continue; }
            if (ch == ';') { pushToken(makeStr(TokenKind.SemiColon, ";", loffset-1, line)); continue; }
            if (ch == ':') { pushToken(makeStr(TokenKind.Colon,     ":", loffset-1, line)); continue; }
            if (ch == ',') { pushToken(makeStr(TokenKind.Comma,     ",", loffset-1, line)); continue; }
            if (ch == '[') { pushToken(makeStr(TokenKind.LBracket,  "[", loffset-1, line)); continue; }
            if (ch == ']') { pushToken(makeStr(TokenKind.RBracket,  "]", loffset-1, line)); continue; }
            if (ch == '%') { pushToken(makeStr(TokenKind.Modulo,    "%", loffset-1, line)); continue; }
            if (ch == '.') { pushToken(makeStr(TokenKind.Dot,       ".", loffset-1, line)); continue; }

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

//

/**************
* PARSER
*/

// NODES

enum NodeKind : ubyte {
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
    // TODO:
    FuncDecl,
    ClassDecl,
    ArrayLit,
    SwitchStmt,
    ForStmt,
    ForEachStmt,
    RequireStmt, // require and require_once
    IncludeStmt, // include and include_once
}

struct Program {
    Node[] body;
}

struct AssignDecl {
    Node* target, value; // $x = 10
}

struct Identifier {
    string value; // x
}

struct DIdentifier {
    string value; // $x
}

struct IntLit {
    long value;
}

struct FloatLit {
    double value;
}

struct StringLit {
    const(char)[] value;
}

struct BinaryExpr {
    Node* right, left;
    string op; // +, +=, /=, ...
}

struct EchoStmt {
    Node* value;
}

struct IfStmt {
    Node* condition;
    Node* body;
    Node* elseBody;
}

struct BlockStmt {
    Node[] body;
}

struct Node {
    NodeKind kind;
    Position pos;
    union {
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
    }
}

// PARSER

enum Precedence : ubyte {
    Low,
    Assign, // =, +=, ...
    Sum, // +, -
    Mul, // *, /, %
    Call, // ms()
    Highest = 69,
}

struct ParseStatement {
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
            case TokenKind.LBrace:
                Node* n = new Node();
                n.kind = NodeKind.BlockStmt;
                while (!parser.check(TokenKind.RBrace) && !parser.isAtEnd())
                    n.block.body ~= *parser.parse();
                enforce(parser.advance().kind == TokenKind.RBrace, "Expected '}' after the block statement.");
                return n;
            case TokenKind.Echo:
                Node* n = new Node();
                n.kind = NodeKind.EchoStmt;
                n.echo.value = parser.expr.parse();
                return n;
            default:
                return null;
        }
    }

    Node* parseIfStmt()
    {
        enforce(parser.advance().kind == TokenKind.LParen, "Expected '(' after 'if'.");
        Node* cond = parser.expr.parse();
        enforce(parser.advance().kind == TokenKind.RParen, "Expected ')' after the expression.");
        Node* body = parser.peek().kind == TokenKind.LBrace ? parse() : parser.parse();
        Node* elseBody = null;
        if (parser.peek().kind == TokenKind.Else)
        {
            parser.advance();
            elseBody = parser.peek().kind == TokenKind.LBrace ? parse() : parser.parse();
        }
        Node* n = new Node();
        n.kind = NodeKind.IfStmt;
        n.ifStmt.condition = cond;
        n.ifStmt.body = body;
        n.ifStmt.elseBody = elseBody;
        return n;
    }
}

struct ParseDecl {
    Parser* parser;

    this(Parser* p)
    {
        this.parser = p;
    }
    
    Node* parse()
    {
        return null;
    }
}

struct ParseExpression {
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
                enforce(parser.advance().kind == TokenKind.RParen, "Expected ')' after this expr.");
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
            default:
                return Precedence.Low;
        }
    }
}

struct Parser {
    uint offset;
    Token[] tokens;
    ParseDecl decl;
    ParseExpression expr;
    ParseStatement stmt;

    void setup()
    {
        this.decl = ParseDecl(&this);
        this.expr = ParseExpression(&this);
        this.stmt = ParseStatement(&this);
    }
    
    @disable this(this); // desabilita cópias por segurança

    Node* parse()
    {
        if (peek().kind == TokenKind.SemiColon) { offset++; return parse(); }
        if (peek().kind == TokenKind.Eof) { offset++; return null; }
        if (isDecl()) return decl.parse();
        if (isStmt()) return stmt.parse();
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
            Node* n = parse();
            if (n !is null) nodes ~= *n;
            else offset++;
        }
        p.program.body = nodes;
        return p;
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
            if (p == k) { offset++; return true; }
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

struct Compiler {
    Node* program;
    uint[] instructions;
    // TODO:
    // uint[string] instructions;
    // string label = "main";
    HVMValue* pool;
    uint poolSz = 0;
    uint[string] stringCache;

    this(Node* program)
    {
        this.program = program;
        this.pool = cast(HVMValue*) malloc(HVMValue.sizeof * 64);    
    }

    pragma(inline, true);
    void push(uint u)
    { this.instructions ~= u; }

    ushort internString(const(char)[] str)
    {
        string key = str.idup;
        
        if (auto idx = key in stringCache)
            return cast(ushort) *idx;
        
        ushort idx = cast(ushort) poolSz;
        char* strCopy = cast(char*) malloc(str.length + 1);
        memcpy(strCopy, str.ptr, str.length);
        strCopy[str.length] = '\0';
        
        pool[poolSz++] = HVMValue.makeString(strCopy, cast(uint)str.length);
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
        if (op == "+") opcode = HVMOpCode.Add;
        else if (op == "-") opcode = HVMOpCode.Sub;
        else if (op == "*") opcode = HVMOpCode.Mul;
        else if (op == "/") opcode = HVMOpCode.Div;
        push(encode_abc(opcode));
    }

    void compileEchoStmt(Node* node)
    {
        compile(node.echo.value);
        push(HVMOpCode.Echo);
    }

    void compile(Node* node)
    {
        switch (node.kind)
        {
            case NodeKind.AssignDecl:  compileAssignDecl(node); break;
            case NodeKind.Identifier:  compileIdentifier(node); break;
            case NodeKind.DIdentifier: compileDIdentifier(node); break;
            case NodeKind.IntLit:      compileIntLit(node); break;
            case NodeKind.StringLit:   compileStrLit(node); break;
            case NodeKind.FloatLit:    compileFloatLit(node); break;
            case NodeKind.BinaryExpr:  compileBinaryExpr(node); break;
            case NodeKind.EchoStmt:    compileEchoStmt(node); break;
            default:
                writeln(node.kind);
                throw new Exception("Unknown node in compiler.");
                return;
        }
    }

    ref uint[] compile()
    {
        Node[] body = program.program.body;
        foreach (ref Node n; body) compile(&n);
        instructions ~= HVMOpCode.Hlt;
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

        Parser parser = Parser(0, tokens);
        parser.setup();
        Node program = parser.parseProgram();

        // foreach (Node n; program.program.body)
        //     writeln(n);

        Compiler compiler = Compiler(&program);
        uint[] p = compiler.compile();
        uint* prog = cast(uint*) malloc(uint.sizeof * p.length);
        foreach (k, v; p) prog[k] = v;

        HVM vm = HVM(prog, cast(uint)p.length, compiler.pool, compiler.poolSz, false);
        vm.run();

        scope(exit) if (compiler.pool !is null) free(compiler.pool);

    } catch (Exception e)
    {
        writeln("Fatal error: ", e.msg);
        writeln("On File: ", e.file);
        writeln("On Line: ", e.line);     
    }
}

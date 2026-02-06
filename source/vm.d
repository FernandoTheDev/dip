module vm;

@nogc:
extern(C):

import core.stdc.stdio, core.stdc.stdlib;
import hm;

enum HVMType : ubyte {
    Bool, //      i1  1 byte (1 bit)
    Char, //      i8  1 byte
    Int, //       i64 8 bytes
    Float, //     f64 8 bytes
    String, //    struct HVMString
    HashTable, // struct HVMHashTable
    Object, //    struct HVMObject
}

struct HVMString {
    char* value;
    uint length;
}

struct HVMHashTable {}
struct HVMObject {}


union HVMLiteral {
    long i32;
    byte i8; // char
    bool i1;
    double f32;
    HVMString str;
    HVMHashTable ht;
    HVMObject obj;
}

struct HVMValue {
@nogc:
    HVMType type; // 1 byte
    HVMLiteral value;

    pragma(inline, true);
    static HVMValue makeInt(long n)
    {
        HVMValue v = HVMValue(HVMType.Int);
        v.value.i32 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeChar(int n)
    {
        return makeChar(cast(char)n);
    }

    pragma(inline, true);
    static HVMValue makeChar(char n)
    {
        HVMValue v = HVMValue(HVMType.Char);
        v.value.i8 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeBool(bool n)
    {
        HVMValue v = HVMValue(HVMType.Bool);
        v.value.i1 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeString(char* str, uint len)
    {
        HVMValue v = HVMValue(HVMType.String);
        v.value.str = HVMString(str, len);
        return v;
    }

    pragma(inline, true);
    static HVMValue makeFloat(double n)
    {
        HVMValue v = HVMValue(HVMType.Float);
        v.value.f32 = n;
        return v;
    }
}

enum HVMOpCode : ubyte {
    // core
    Store, // store "x"
    Load,  // load "x"
    Loadk, // carrega uma constante do pool
    Loadkx, // carregar uma constante com IDX grande do pool
    Call, // chamada em função normal com `ret`
    Callb, // chamada em função builtin
    Callf, // chamada em função ffi
    Ret, // retorna pro `pc` anterior
    Echo,
    
    // genericos pra qualquer tipo prevalecendo o tipo maior, suportam fastPath para operações com o mesmo tipo
    // prefixo B indica BitWise
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /

    BShl, // >>
    BShll, // >>>
    BShr, // <<
    BXor, // ^
    BAnd, // &
    Bor, // |
    BNot, // ~
    
    
    Jmp,
    Jz, //  jmp if zero (false)
    Jnz, // jmp if not zero (true)
    // toda condição retorna um bool que pode ser 1 ou 0 (true ou false)
    Lt, // <
    Gt, // >
    Lte, // <=
    Gte, // >=
    Eq, // ==
    Neq, // !=
    
    Hlt, // Halt
}

struct FrameCall {
    HashMap!(string, HVMValue) context;
    uint retAddr;
}

struct HVM {
@nogc:
    uint* program; // programa
    uint pc; // contador do programa
    uint programSize; // tamanho do programa
    HVMValue* constantPool; // mapa de constantes
    uint constantPoolSize; // tamanho do mapa de constantes
    const ubyte STACK_LIMIT = 255;
    HVMValue[STACK_LIMIT] stack = []; // a pilha do programa
    uint stackSize;
    HashMap!(string, HVMValue) context;
    // uint* frameCall; // salva o pc de cada chamada
    // uint fcIdx; // salva o ultimo idx
    // uint fcSizeFix; // tamanho em relação ao *frameCall
    bool clean = true;
    
    this(uint* program, uint programSize, HVMValue* constantPool, uint constantPoolSize, bool clean = true)
    {
        this.program = program;
        this.programSize = programSize;
        this.constantPool = constantPool;
        this.constantPoolSize = constantPoolSize;
        this.clean = clean;
        context.initialize(255);
        // this.frameCall = cast(uint*) malloc(uint.sizeof * 1000); // 4kb
        // this.fcSizeFix = 1000; // em caso de realloc isso aqui vai mudar
    }

    ~this() 
    {
        this.clear();
    }

    pragma(inline, true);
    void clear()
    {
        if (clean)
        {
            if (program !is null)
                free(program);
            if (constantPool !is null)
                free(constantPool);
        }
        // if (frameCall !is null)
        //     free(frameCall);
    }

    pragma(inline, true);
    void error(string msg)
    {
        printf("HVM Internal error: %s", cast(const char*)msg);
        exit(EXIT_FAILURE);
    }

    pragma(inline, true);
    HVMValue pop()
    {
        if (stackSize < 1)
            this.error("Stack Underflow.");
        return stack[--stackSize];
    }

    pragma(inline, true);
    void push(HVMValue val)
    {
        if (stackSize == STACK_LIMIT)
            this.error("Stack Overflow.");
        stack[stackSize++] = val;
    }

    void run()
    {
        while (pc < programSize)
        {
            uint instr = program[pc++];
            ubyte opcode = instr & 0xFF;

            // printf("opcode: %d\n", opcode);
            
            final switch (opcode)
            {
                case HVMOpCode.Loadk: opLoadk(instr >> 8 & 0xFFFF); continue;
                case HVMOpCode.Store: opStore(); continue;
                case HVMOpCode.Load:  opLoad();  continue;
                case HVMOpCode.Add:   opAdd();   continue;
                case HVMOpCode.Sub:   opSub();   continue;
                case HVMOpCode.Mul:   opMul();   continue;
                case HVMOpCode.Div:   opDiv();   continue;
                case HVMOpCode.Echo:  opEcho();  continue;
                case HVMOpCode.Eq:
                case HVMOpCode.Jmp:
                case HVMOpCode.Jz:
                case HVMOpCode.Jnz:

                case HVMOpCode.Call:
                case HVMOpCode.Ret:
                
                case HVMOpCode.BShl:
                case HVMOpCode.BShll:
                case HVMOpCode.BShr:
                case HVMOpCode.BXor:
                case HVMOpCode.BAnd:
                case HVMOpCode.BNot:
                case HVMOpCode.Bor:
                
                case HVMOpCode.Lt:
                case HVMOpCode.Gt:
                case HVMOpCode.Lte:
                case HVMOpCode.Gte:
                case HVMOpCode.Neq:

                case HVMOpCode.Loadkx:
                case HVMOpCode.Callb:
                case HVMOpCode.Callf:
                case HVMOpCode.Hlt:
                    return;
            }
        }
    }

    pragma(inline, true);
    void opEcho()
    {
        HVMValue val = pop();
        switch (val.type)
        {
            case HVMType.String: printf("%s",   val.value.str.value); break;
            case HVMType.Int:    printf("%lld", val.value.i32); break;
            case HVMType.Float:  printf("%f",   val.value.f32); break;
            case HVMType.Char:   printf("%c",   val.value.i8); break;
            case HVMType.Bool:   printf("%s",   val.value.i1 ? cast(char*)"true" : cast(char*)"false"); break;
            default:             printf("<err>"); break;
        }
    }

    pragma(inline, true);
    void opStore()
    {
        HVMValue idx = pop();
        HVMValue val = pop();
        string key = cast(string) idx.value.str.value[0 .. idx.value.str.length];   
        context.put(key, val);
    }

    pragma(inline, true);
    void opLoad()
    {
        HVMValue idx = pop();
        string key = cast(string) idx.value.str.value[0 .. idx.value.str.length];
        HVMValue* val = context.get(key);
        if (val !is null) push(*val); else push(HVMValue.init);
    }

    pragma(inline, true);
    void opAdd()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        // evita que strings ou outros tipos não literais sejam passados aqui
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform the addition operation with these types.");
        // tenta fastPath
        if (l.type == r.type)
            switch (l.type)
            {
                case HVMType.Int:    push(HVMValue.makeInt(l.value.i32 + r.value.i32));                  return;
                case HVMType.Char:   push(HVMValue.makeChar(cast(byte)(l.value.i8 + r.value.i8)));       return;
                case HVMType.Float:  push(HVMValue.makeFloat(l.value.f32 + r.value.f32));                return;
                default:             error("Unknown type in addition operation.");                       return;
            }
        opAddSlowPath(l, r);
    }

    pragma(inline, true);
    void opAddSlowPath(HVMValue l, HVMValue r)
    {
        // define o tipo pelo nivel de cada tipo
        // a enum de tipos está na ordem certa
        // isso é mais que suficiente pra cast automatico
        HVMType t = l.type > r.type ? l.type : r.type;
        // printf("[DEBUG] slow path\n");
        switch (t)
        {
            case HVMType.Int:    push(HVMValue.makeInt(toInt(l).value.i32                    + toInt(r).value.i32));        
                return;
            case HVMType.Char:   push(HVMValue.makeChar(cast(byte)(toChar(l).value.i8        + toChar(r).value.i8)));       
                return;
            case HVMType.Float:  push(HVMValue.makeFloat(toFloat(l).value.f32                + toFloat(r).value.f32));      
                return;
            default:             error("Error on add slow path."); break;
        }
    }

    pragma(inline, true);
    void opSub()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        // evita que strings ou outros tipos não literais sejam passados aqui
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform subtraction with these types.");
        // tenta fastPath
        if (l.type == r.type)
            switch (l.type)
            {
                case HVMType.Int:    push(HVMValue.makeInt(l.value.i32 - r.value.i32));                  return;
                case HVMType.Char:   push(HVMValue.makeChar(cast(byte)(l.value.i8 - r.value.i8)));       return;
                case HVMType.Float:  push(HVMValue.makeFloat(l.value.f32 - r.value.f32));                return;
                default:             error("Unknown type in subtraction operation.");                    return;
            }
        opSubSlowPath(l, r);
    }

    pragma(inline, true);
    void opSubSlowPath(HVMValue l, HVMValue r)
    {
        HVMType t = l.type > r.type ? l.type : r.type;
        // printf("[DEBUG] slow path\n");
        switch (t)
        {
            case HVMType.Int:    push(HVMValue.makeInt(toInt(l).value.i32       - toInt(r).value.i32));        return;
            case HVMType.Char:   push(HVMValue.makeChar(toChar(l).value.i8      - toChar(r).value.i8));        return;
            case HVMType.Float:  push(HVMValue.makeFloat(toFloat(l).value.f32   - toFloat(r).value.f32));      return;
            default:             error("Error on sub slow path."); break;
        }
    }

    pragma(inline, true);
    void opMul()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        // evita que strings ou outros tipos não literais sejam passados aqui
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform multiplication operations with these types.");
        // tenta fastPath
        if (l.type == r.type)
            switch (l.type)
            {
                case HVMType.Int:    push(HVMValue.makeInt(l.value.i32 * r.value.i32));                  return;
                case HVMType.Char:   push(HVMValue.makeChar(cast(byte)(l.value.i8 * r.value.i8)));       return;
                case HVMType.Float:  push(HVMValue.makeFloat(l.value.f32 * r.value.f32));                return;
                default:             error("Unknown type in multiplication operation.");                 return;
            }
        opMulSlowPath(l, r);
    }

    pragma(inline, true);
    void opMulSlowPath(HVMValue l, HVMValue r)
    {
        HVMType t = l.type > r.type ? l.type : r.type;
        // printf("[DEBUG] slow path\n");
        switch (t)
        {
            case HVMType.Int:    push(HVMValue.makeInt(toInt(l).value.i32       * toInt(r).value.i32));        return;
            case HVMType.Char:   push(HVMValue.makeChar(toChar(l).value.i8      * toChar(r).value.i8));        return;
            case HVMType.Float:  push(HVMValue.makeFloat(toFloat(l).value.f32   * toFloat(r).value.f32));      return;
            default:             error("Error on mul slow path."); break;
        }
    }

    pragma(inline, true);
    void opDiv()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        // evita que strings ou outros tipos não literais sejam passados aqui
        if (l.type >= HVMType.String || r.type >= HVMType.String)
            error("It is not possible to perform the division operation with these data types.");
        // tenta fastPath
        if (l.type == r.type)
            switch (l.type)
            {
                case HVMType.Int:    
                    check(r.value.i32 != 0, "Div by zero.");
                    push(HVMValue.makeInt(l.value.i32 / r.value.i32));                  return;
                case HVMType.Char:   
                    check(r.value.i8 != 0, "Div by zero.");
                    push(HVMValue.makeChar(cast(byte)(l.value.i8 / r.value.i8)));       return;
                case HVMType.Float:  
                    check(r.value.f32 != 0.0, "Div by zero.");
                    push(HVMValue.makeFloat(l.value.f32 / r.value.f32));                return;
                default: error("Unknown type in the division operation.");              return;
            }
        opDivSlowPath(l, r);
    }

    pragma(inline, true);
    void opDivSlowPath(HVMValue l, HVMValue r)
    {
        // define o tipo pelo nivel de cada tipo
        // a enum de tipos está na ordem certa
        // isso é mais que suficiente pra cast automatico
        HVMType t = l.type > r.type ? l.type : r.type;
        // printf("[DEBUG] slow path\n");

        HVMValue lConverted, rConverted;

        switch (t)
        {
            case HVMType.Int:    
                lConverted = toInt(l);
                rConverted = toInt(r);
                check(rConverted.value.i32 != 0, "Div by zero.");
                push(HVMValue.makeInt(lConverted.value.i32 / rConverted.value.i32));
                return;

            case HVMType.Char:   
                lConverted = toChar(l);
                rConverted = toChar(r);
                check(rConverted.value.i8 != 0, "Div by zero.");
                push(HVMValue.makeChar(lConverted.value.i8 / rConverted.value.i8));
                return;

            case HVMType.Float:  
                lConverted = toFloat(l);
                rConverted = toFloat(r);
                check(rConverted.value.f32 != 0.0, "Div by zero.");
                push(HVMValue.makeFloat(lConverted.value.f32 / rConverted.value.f32));
                return;

            default:             
                error("Error on div slow path."); 
                break;
        }
    }

    pragma(inline, true);
    HVMValue toInt(HVMValue val)
    {
        switch (val.type)
        {
            case HVMType.Int:    return val;
            case HVMType.Char:   return HVMValue.makeInt(cast(long)val.value.i8);
            case HVMType.Float:  return HVMValue.makeInt(cast(long)val.value.f32);
            case HVMType.Bool:   return HVMValue.makeInt(cast(long)val.value.i1);
            default:
                error("It's not possible to convert this type to an integer.");
                break;
        }
        // nunca é retornando porque vai dar erro antes
        return HVMValue.init;
    }

    pragma(inline, true);
    HVMValue toFloat(HVMValue val)
    {
        switch (val.type)
        {
            case HVMType.Float:  return val;
            case HVMType.Int:    return HVMValue.makeFloat(cast(double)val.value.i32);
            case HVMType.Char:   return HVMValue.makeFloat(cast(double)val.value.i8);
            case HVMType.Bool:   return HVMValue.makeFloat(cast(double)val.value.i1);
            default:
                error("It's not possible to convert this type to a float.");
                break;
        }
        return HVMValue.init;
    }

    pragma(inline, true);
    HVMValue toBool(HVMValue val)
    {
        switch (val.type)
        {
            case HVMType.Bool:   return val;
            case HVMType.Int:    return HVMValue.makeBool(val.value.i32 != 0);
            case HVMType.Char:   return HVMValue.makeBool(val.value.i8 != 0);
            case HVMType.Float:  return HVMValue.makeBool(val.value.f32 != 0.0f);
            default:
                error("It's not possible to convert this type to a bool.");
                break;
        }
        return HVMValue.init;
    }

    pragma(inline, true);
    HVMValue toChar(HVMValue val)
    {
        switch (val.type)
        {
            case HVMType.Char:   return val;
            case HVMType.Int:    
                check(val.value.i32 >= byte.min && val.value.i32 <= byte.max, "Char overflow/underflow.");
                return HVMValue.makeChar(cast(byte)val.value.i32);
            case HVMType.Float:  return HVMValue.makeChar(cast(byte)val.value.f32);
            case HVMType.Bool:   return HVMValue.makeChar(cast(byte)val.value.i1);
            default:
                error("It's not possible to convert this type to a char.");
                break;
        }
        return HVMValue.init;
    }

    pragma(inline, true);
    string typeToString(HVMType t)
    {
        switch (t)
        {
            case HVMType.String: return "string";
            case HVMType.Int:    return "int";
            case HVMType.Float:  return "float";
            case HVMType.Char:   return "char";
            case HVMType.Bool:   return "bool";
            default:             return "<err>";
        }
    }

    pragma(inline, true);
    void opLoadk(ushort idx)
    {
        if (idx > constantPoolSize || constantPoolSize == 0)
            error("The passed index exceeds the size of the constant map.");
        if (stackSize == STACK_LIMIT)
            error("The stack is already full to its maximum limit, it is not possible to perform a 'Loadk'.");
        stack[stackSize++] = constantPool[idx];
    }
}

void check(bool result, string message)
{
    if (result) return;
    printf("HVM Error: %s\n", cast(char*)message);
    exit(EXIT_FAILURE);
}

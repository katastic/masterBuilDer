/// 2024, Katastic
/// We could do some sort of get pointer for verbosewriteln so you cannot get it without setting it.
/// we want this pointer method so we don't couple the APIs
/// however, doing just the function lets us mimic the normal writeln, writefln 
/// by just adding the 'verbose' prefix. So for that, the setup method is okay.
module utility;
import toml;
import std.array;
import std.stdio : writeln, writefln;
import std.string : indexOfAny;
import std.algorithm : map;

alias fileHashes = string[string];
bool *doVerboseMode;

void setVerboseModeVariable(bool *_doVerboseMode){
    doVerboseMode = _doVerboseMode;
    }

bool isAny(string src, string match){ return (src.indexOfAny(match) != -1); } /// Is any string src in match? return: boolean
  
/// Is there any string src in match after AfterThis matches? return: boolean. false if either condition fails
bool isAnyAfter(string src, string match, string afterThis){    
	return (src.indexOfAny(afterThis) != -1) && (src.indexOfAny(match) != -1);
	}

string[] convTOMLtoArray(TOMLValue t){ 
	return t.array.map!((o) => o.str).array;
	}

/// Only print if doPrintVerbose is true, exact replacement for writeln
void verboseWriteln(A...)(A a){  // todo: what about fln version. Pass in a std.format is all needed?
    assert(doVerboseMode !is null);
	if(doVerboseMode)foreach(t; a)writeln(t);
	//if(exeConfig.doPrintVerbose)foreach(t; a)writeln(t);
	}

/// adapted from from function signatures here: https://github.com/dlang/phobos/blob/master/std/stdio.d
void verboseWritefln(alias fmt, A...)(A args){
    assert(doVerboseMode !is null);
    if (isSomeString!(typeof(fmt))){
		if(doVerboseMode)return;
        return writefln(fmt, args);
        }
    }

/// adapted from from function signatures here: https://github.com/dlang/phobos/blob/master/std/stdio.d
void verboseWritefln(Char, A...)(in Char[] fmt, A args){
    assert(doVerboseMode !is null);
    if(doVerboseMode)return;
    writefln(fmt, args);
    }


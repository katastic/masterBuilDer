/// 2024, Katastic
/// We could do some sort of get pointer for verbosewriteln so you cannot get it without setting it.
/// we want this pointer method so we don't couple the APIs
/// however, doing just the function lets us mimic the normal writeln, writefln 
/// by just adding the 'verbose' prefix. So for that, the setup method is okay.
module utility;
import toml;
import std.array;
import std.stdio : write, writeln, writefln;
import std.string : indexOfAny;
import std.algorithm : map;

alias fileHashes = string[string];
__gshared bool *doVerboseMode;

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
void verboseWrite(A...)(A a){  // todo: what about fln version. Pass in a std.format is all needed?
    assert(doVerboseMode !is null, "doVerboseMode pointer is null!");
	if(!*doVerboseMode)return;
	foreach(t; a)write(t);	
	//if(exeConfig.doPrintVerbose)foreach(t; a)writeln(t);
	}

/// Only print if doPrintVerbose is true, exact replacement for writeln
void verboseWriteln(A...)(A a){  // todo: what about fln version. Pass in a std.format is all needed?
    assert(doVerboseMode !is null, "doVerboseMode pointer is null!");
	if(!*doVerboseMode)return;
	foreach(t; a)writeln(t);	
	//if(exeConfig.doPrintVerbose)foreach(t; a)writeln(t);
	}

/// adapted from from function signatures here: https://github.com/dlang/phobos/blob/master/std/stdio.d
void verboseWritefln(alias fmt, A...)(A args){
    assert(doVerboseMode !is null, "doVerboseMode pointer is null!");
    if (isSomeString!(typeof(fmt))){
		if(!*doVerboseMode)return;
        return writefln(fmt, args);
        }
    }

/// adapted from from function signatures here: https://github.com/dlang/phobos/blob/master/std/stdio.d
void verboseWritefln(Char, A...)(in Char[] fmt, A args){
    assert(doVerboseMode !is null, "doVerboseMode pointer is null!");
    if(!*doVerboseMode)return;
    writefln(fmt, args);
    }

bool isFirstLetterDot(string name){
	assert(name.length > 1);
	return (name[0] == '.');
	}

import std.file : DirEntry;
bool isHidden(DirEntry de){                             /// Because D is dumb and keeps attributes in OS specific format.			
	version(Windows){
		enum FILE_ATTRIBUTE_HIDDEN = 0x02;
		return cast(bool)(de.attributes & FILE_ATTRIBUTE_HIDDEN); //https://learn.microsoft.com/en-us/windows/win32/fileio/file-attribute-constants
		}
	version(linux){
		return de.isFirstLetterDot;
		}
	assert(0, "OS not implemented");
	}

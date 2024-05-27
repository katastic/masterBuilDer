/++ 
 * Questions
	- is dub really so shit it doesn't even display how to run a program and pass an argument in the --help?

	dub run -- [commandline args] works though.
 +/
import std.process, std.path, std.stdio;
import std.digest.crc, std.format, std.file;
import toml;

string lastBuildFileName = "lastBuild.toml";

final class fileCacheList{
	string dir;

	this(string[] files){
		import std.digest;
		import std.digest.crc;

		writeln("fileCacheList");
		foreach(f; files){
			writefln("\t%60s - %s", f, toHexString!(LetterCase.lower)(digest!CRC32(readText(f))));
			}
		}

    /+this(string directoryPath){
		assert(directoryPath !is null);
		dir = directoryPath;

		getFileList();
        }

    void getFileList(){
   
            }  
    } +/
    void getFileList(){} // how does this compile
    }

struct modeStringConfig{
	string[] modePerCompiler;
	}

struct globalConfiguration{
	//modeStringConfig[] modeStrings; /// e.g. "debug"=["debug"] mode string, "profile"=["release","profile"] mode strings
	modeStringConfig[string] modeStrings;
	//string[] modeStrings; /// debug = ["-debug"]
	}
globalConfiguration globalConfig;
targetConfiguration[string] tConfigs;

struct targetConfiguration{ // windows, linux, etc
	string target;
	string compilerName;
	string[] sourcePaths;
	string[] recursiveSourcePaths;
	string[] libPaths;
	string[] recursiveLibPaths;
	string[] libs;

	// enumerated data
	string[] sourceFilesFound;
}

struct profileConfiguration{ // are we using these?? are they profiles???
	//string target; // windows, linux, etc
	// string name- name is now the KEY of the AA
	string mode; /// full mode string ala "-d -debug -o"
	}

profileConfiguration[string] runToml(){
	import std.experimental.logger;
	import toml;
	import std.ascii : newline;
	import std.exception : enforce, assertThrown;
	import std.math : isNaN, isFinite, isClose;
	import std.conv : to;
	import std.file : read;
	TOMLDocument doc;

	writeln(readText("buildConfig.toml"));
	doc = parseTOML(cast(string)read("buildConfig.toml"));
	
	auto compilers = doc["project"]["compilers"].array;
	foreach(c; compilers){
		writeln("compilers found: ", c);
		}
	
	auto targets = doc["project"]["targets"].array;
	foreach(t; targets){
		writeln("targets found: ", t);
		}

	template wrapInException(string code){
		import std.format;		
    	const char[] wrapInException = format("
			{
				try{
				
					%s	// FIX ME <--------------------------

				}catch(Exception e){
					writeln(\"Exception occured: \", e);
				}
			}", scanPathVar);
		}
	writeln();

	foreach(m, n; doc["modeStrings"]){
		//pragma(msg, typeof(m));
		//pragma(msg, typeof(n));
		//writeln("1 ", m.type); // string
		writeln("[",m, "] = ", n[0], "/", n[1], " of type ", n.type); // string
		string tempString;
		modeStringConfig _modeString;
		foreach(t; n.array){_modeString.modePerCompiler ~= t.str;}
		globalConfig.modeStrings[m] = _modeString;
		}
	writeln(globalConfig);	

	string[] convTOMLtoArray(TOMLValue t){ 
		import std.algorithm : map;
		import std.array : array;
//		string[] strings; foreach(value; t.array){strings ~= value.str;} // works
		return t.array.map!((o) => o.str).array;
		}

	foreach(t; targets){
		targetConfiguration tc;
		writeln("doc", t.str);
		auto d = doc[t.str];
		tc.target = t.str;
	//	foreach(value; d["sourcePaths"].array){cc.sourcePaths ~= value.str;}
		writeln("TEST");
		tc.sourcePaths 			= convTOMLtoArray(d["sourcePaths"]);
		tc.recursiveSourcePaths = convTOMLtoArray(d["recursiveSourcePaths"]);
		tc.libPaths 			= convTOMLtoArray(d["libPaths"]); 
		tc.recursiveLibPaths 	= convTOMLtoArray(d["recursiveLibPaths"]);
		tc.libs 				= convTOMLtoArray(d["libs"]);
		writeln("TEST2");
		string FIXME = r""; /// working directory fix
		foreach(path; tc.sourcePaths){
			mixin(wrapInException!"path");
			}
		tConfigs[t.str] = tc;
		writeln("Source files found: ", tc.sourceFilesFound);
		}
	profileConfiguration[string] pConfigs;
	int chosenCompiler = 0; // FIXME
	foreach(mode; doc["project"]["profiles"].array){
		string name = mode.str;
		writeln("Reading profile: ", name); // "debug", "release"
		
		auto buildProfileData = doc[mode.str];
		writeln("\t", buildProfileData);
		profileConfiguration pc;
		auto modeArray = buildProfileData["modesEnabled"].array; // selected modes for configuration
		string temp;
		foreach(m; modeArray){
			writeln("\tfound mode ", m.str);
			temp ~= globalConfig.modeStrings[m.str].modePerCompiler[chosenCompiler] ~ " ";
			}
		pc.mode = temp;
		writefln("\tfull mode string [%s]", temp);		
		pConfigs[name] = pc;
		}

	return pConfigs;
	}

struct exeConfigType{
	bool doRunCompiler = false;
	string modeSet="default"; // todo: change to enum or whatever
	
	string selectedProfile = "release";
	string selectedCompiler = "dmd";
	string selectedTargetOS = "";  // set by version statement in main.

	string extraCompilerFlags = "";
	string extraLinkerFlags = "";
	}

void displayHelp(){
	writeln("");
	writeln("  masterBuilder[.exe] [command] [option=value] [option=value] -- args");
	writeln("");
	writeln("\trun   - run the program");
	writeln("\tbuild - actually build");
	writeln("\tcheck - check if any files have changed and list them.");
	writeln("\ttry   - see if the build config would produce a compiler command");
	writeln("\tlint  - run DScanner");
	writeln("\tquote - recieve a verse about the Master Builder");
	writeln("\thelp  - this help screen.");
	writeln("");
	writeln("\tOptions:");
	writeln("\t\tprofile=name/of/profile (profile=release, profile=debug, etc)");
	writeln("\t\ttarget=windows/linux (try using commands for a different OS.)");
	writeln("\t\tcompilerflags=\"taco is a bad man\" (use shell quotes for strings with spaces) ");
	writeln("\t\tlinkerflags=--test                  (quotes not required if no spaces)");
	writeln("");
	writeln("\tFor passing commandline arguments to the program, use -- to end");
	writeln("\t  internal processing of args and send them to the program.");
	writeln("");
	writeln("\tExample usage:");
	writeln("");
	writeln("\t masterBuilder build profile=debug -- hello!");
	writeln("\t  - build profile named debug, run, and pass it \"hello!\" ");
	}

void displayQuote(){
	import quotes, std.random;
	writefln("\"%s\"", quoteStrings[ uniform!"[]"(0, cast(int)quoteStrings.length-1)] );
	}

void runLint(){
	}

int parseModeInit(string arg){
	import std.string;
	writefln("parseModeInit(%s)", arg);
	switch(arg.strip){
		case "build": exeConfig.doRunCompiler = true ; exeConfig.modeSet = "build"; return 0; break;
		case "try"  : exeConfig.doRunCompiler = false; exeConfig.modeSet = "build"; return 0; break;
		case "quote": displayQuote(); return 0; break;
		case "lint" : runLint(); return 0; break;
		case "help" : case "man": displayHelp(); return 0; break;
		default     : displayHelp();return 0; break;
		}
	terminateEarlyString(arg);	
	return -1;
	}

int parseModeBuild(string arg){
	import std.string;
	bool isAny(T, string V) => (T.indexOfAny(V) != -1);

	writefln("parseModeBuild(%s)", arg);	
	long n = arg.indexOfAny("=");
	if(n == -1){writeln("Missing equals?"); terminateEarlyString(arg); return -1;} // args must be in key=value, so if there's no equal it's invalid.
	writefln("matching [%s] = [%s]", arg[0..n], arg[n+1..$]);
	string option=arg[0..n];
	string value=arg[n+1..$];
	// note we ONLY change case of option! We don't want to
	//  accidentally change case of a compiler flag string!
	switch(option.toLower){
		case "profile":
			writeln("Setting profile=", value);
			exeConfig.selectedProfile = value;
			// look for profile names? We need to scan profiles before this?
			// or just let it rangeException out later.
			return 0;
		break;
		case "target":
			writeln("Setting target=", value);
			exeConfig.selectedTargetOS = value;
			return 0;
		break;
		case "compiler":
			writeln("Setting compiler=", value);
			exeConfig.selectedCompiler = value;
			return 0;
		break;
		case "compilerflags":
			writeln("Setting compilerflags=", value);
			if(value.isAny(" "))
				exeConfig.extraCompilerFlags = "\"" ~ value ~ "\""; // [myString stuff] becomes ["myString stuff"]
				 // .replace("\"", "\\\"")  but how do we handle embedded strings? What does OS send? Maybe already good enough.
			else
				exeConfig.extraCompilerFlags = value;
			return 0;
		break;
		case "linkerflags":
			writeln("Setting linkerflags=", value);
			if(value.isAny(" "))
				exeConfig.extraLinkerFlags = "\"" ~ value ~ "\""; // [myString stuff] becomes ["myString stuff"]
				 // .replace("\"", "\\\"")  but how do we handle embedded strings? What does OS send? Maybe already good enough.
			else
				exeConfig.extraLinkerFlags = value;
			return 0;
		break;
		default:
		terminateEarlyString(arg);
		return -1;
		break;
		}
	assert(0, "this shouldn't happen. (Did the dev forget a switch return?)");
	return -1;
	}

void terminateEarlyString(string arg){
	writeln("Unrecognized command: ", arg);
	displayHelp();
	}

void parseCommandline(string[] myArgs){
	writeln("args:", myArgs);

	foreach(arg; myArgs){
			if(exeConfig.modeSet=="default"){if(parseModeInit(arg)){return;}}
			else if(exeConfig.modeSet=="build"){if(parseModeBuild(arg)){return;}}
			else if(exeConfig.modeSet=="helper"){displayHelp();}
			else if(exeConfig.modeSet=="quote"){displayQuote();}
		}
	if(exeConfig.modeSet == "build"){
		commandBuild();
		}
	return;
	}

void commandBuild(){
	profileConfiguration[string]  pConfigs = runToml();
	writeln(pConfigs);
    string filesList = "";
    int i = 0;

	writeln("");
	displayQuote();
	writeln("");
    writeln("Files to compile:");
    filesList = "";
	foreach(file; tConfigs[exeConfig.selectedTargetOS].sourceFilesFound){
		filesList ~= file ~ " ";
		}
	writefln("\"%s\"\n", filesList);

	auto fc = new fileCacheList(tConfigs[exeConfig.selectedTargetOS].sourceFilesFound);

    writeln("Library paths:");
	string libPathList = "";
	foreach(libpath; tConfigs[exeConfig.selectedTargetOS].libPaths){
		switch(tConfigs[exeConfig.selectedTargetOS].target){
			case("linux"):   libPathList ~= "-L-L"~libpath~" "; 		break;
			case("windows"): libPathList ~= "-L/LIBPATH:"~libpath~" ";	break;
			default:		 assert(0, format("invalid target name [%s]", exeConfig.selectedProfile)); break;
			}
		}
	writefln("\"%s\"\n", libPathList);

	writeln("");
	writefln("Buildname: %s (%s/%s)", 
		exeConfig.selectedProfile,
		exeConfig.selectedTargetOS, 
		exeConfig.selectedCompiler);
	writeln("");
    string outputName = "main.exe";
    string flags = "-debug -O -d"; // debug symbols, optimze, -d is ignore depreciationn for DAllegro for now
    
	if(exeConfig.doRunCompiler){
		auto dmd = executeShell(
			"dmd -of=" ~ outputName ~ " " ~ flags ~ " " ~
			filesList ~ " " ~ libPathList ~ " " ~ 
			exeConfig.extraCompilerFlags ~ " " ~ 
			exeConfig.extraLinkerFlags);

		if (dmd.status != 0){
			writeln("Compilation failed:\n", dmd.output);        
			}else{
			writefln("Writing to [%s]", outputName);
			writeln("Compilation succeeded:\n\n", dmd.output);
			writeln();
			}
		}
	}

exeConfigType exeConfig;
int main(string[] args){
	version(Windows){
		exeConfig.selectedTargetOS = "windows"; // default to whatever OS it is
	}else{
		exeConfig.selectedTargetOS = "linux"; // default to whatever OS it is
	}
	writeln(args);
	if(args.length > 1){
		parseCommandline(args[1..$]);
		}

    return 0;
	}
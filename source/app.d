/+ 	
	masterBuilDer

	tools we could add:
		- fuzzy importer. Tries to remove each import and see if it still compiles. 
		- create [init] buildscript. Dumps the default values into a TOML file!
		- scan for (remove?) too many repeating newlines (dLawn scripts)
		- [line] counts? pretty simple. Could support random scripts after succeeding builds though.
		- list any FIXME, TODO, etc in source files. also LAST if you want to mark where you worked last at end off day.
		- [unit] tests
		- support ASCII colorizing? re-implement python pygments without having to invoke it or dep on it?
		- for fun: FUZZY FIXER. Use genetic algorithm to try to match nearest wrong/mispelled string to correct one.

	todo:
		- figure out dmd binary file compilation import issue.
		- filesList is a bunch of FILES. We need to trim each `.d` and replace it with `.obj`. 
			- Might be as simple as string replace. But what if some moron has .d _inside_ their filename?
		- what if file is REMOVED?
		- do RECURSIVE file path scans work? And also manual lib names (instead of paths)
		- dump individual compiled files into a temp directory (specified WHERE?)
		- alternate cachefile name
		- why do we SCAN FILES on alternative OS/configurations??? It's just going to exception out.

	- do we store cached files PER PROFILE??? Because if 5we change profile the file caches aren't updated. 
			- Maybe store each profile in its own section.
+/
module app;
import std.process, std.path, std.stdio;
import std.digest.crc, std.format, std.file;
import toml;

alias fileHashes = string[string];

void conditionalCompile(fileHashes filesList){ // used????
	writeln("conditionalCompile()");
	foreach(k,v; filesList){
		writeln(k);
		}
	}

final class fileCacheList{
	string dir;
	fileHashes database;
	fileHashes differencesDb;
	bool foundDifferences = false;
	string[] tempFiles;

	this(string[] filenames){
		tempFiles = filenames;
		differencesDb = compareAndFindDifferences();
		if(differencesDb.length > 0){
			writeln("Found differences:", differencesDb);
			foundDifferences = true;
			}
		}
		
	string[] getDifferences() => differencesDb.keys;

	fileHashes compareAndFindDifferences(){
		fileHashes oldValues 	 = scanCachedHashes();
		fileHashes currentValues = scanHashes(tempFiles);
		if(oldValues.length == 0){ verboseWriteln("No cached data. Enumerating all files."); return currentValues;}
		database = currentValues; // NOTE: SIDE-EFFECT. Calling this updates our perception of database.
		fileHashes differences;

		foreach(k,v; oldValues){    writefln("old    %s %s", k, v);}
		foreach(k,v; currentValues){writefln("cached %s %s", k, v);}

		// what if a file is REMOVED??
		writeln("compareAndFindDifferences() - DIFFERENCES");
		foreach(k, v; currentValues){
			if(k !in oldValues){
				writefln("\t%30s - %s [NEW]", k, v);
				differences[k] = v;
				continue;
				}
			if(currentValues[k] != oldValues[k]){				
				writefln("\t%30s - %s vs %s [DIFF]", k, v, oldValues[k]);
				differences[k] = v;
				} else {
				writefln("\t%30s - %s vs %s [MATCH]", k, v, currentValues[k]);
				}
			}

		// HOW do we detect if the NEW FILE has finished correctly with new files?
		// easiest: only update when compile succeeds.
		// otherwise, store and track executable CRC too?

		// we also want to rebuild EACH FILE to a temp object at some point.
		// and also support CLEAN for cleaning them up
		return differences;
		}
	
	void saveResults(){
		writeNewCachedList(database);
		}

	void writeNewCachedList(fileHashes db){	
		auto file = File(exeConfig.cacheFileName, "w");
		file.writeln("[fileHashes]");

		writeln("OUTPUT TO FILE--> ", exeConfig.cacheFileName);
		foreach(f, hex; db){
			//string hex = toHexString!(LetterCase.lower)(digest!CRC32(readText(f))).dup;
			writefln("\t%30s - %s", f, hex);
			file.writefln("\"%s\" = \"%s\"", f, hex);
			database[f] = hex;
			}
		}

	// TODO: specify alternate build file support in exeConfig or something.
	fileHashes scanCachedHashes(){
		fileHashes results;
		try{
		TOMLDocument doc = parseTOML(cast(string)read(exeConfig.cacheFileName));
		writeln("scanCachedHashes() - ", exeConfig.cacheFileName);
		foreach(f, hex; doc["fileHashes"]){
			writefln("\t%30s - %s", f, hex.str);
			results[f] = hex.str;
			}
		}catch(Exception e){
			writefln("No %s file found, or inaccessable.", exeConfig.cacheFileName); 
		}
		return results;
		}

	string[string] scanHashes(string[] files){
		string[string] results;
		writeln("scanHashes() - fileCacheList:");
		foreach(f; files){
			string hex = toHexString!(LetterCase.lower)(digest!CRC32(readText(f))).dup;
			writefln("\t%30s - %s", f, hex);
			results[f] = hex;
			}
		return results;
		}
	}

struct modeStringConfig{
	string[string] modePerCompiler;
	}

struct globalConfiguration{
	//modeStringConfig[] modeStrings; /// e.g. "debug"=["debug"] mode string, "profile"=["release","profile"] mode strings
	modeStringConfig[string] modeStrings;
	//string[] modeStrings; /// debug = ["-debug"]
	
	// [Options]
	bool automaticallyAddOutputExtension=true;  /// main for linux, main.exe for windows
	}

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

struct profileConfiguration{ 
	string mode; /// full mode string ala "-d -debug -o"
	string outputFilename = "main"; // automatically adds .exe
	}

profileConfiguration[string] runToml(){
	import toml;
	import std.conv : to;
	import std.file : read;
	TOMLDocument doc;

	writeln(readText(exeConfig.buildScriptFileName));
	doc = parseTOML(cast(string)read(exeConfig.buildScriptFileName));
	
	auto compilers = doc["project"]["compilers"].array;
	foreach(c; compilers){
		writeln("compilers found: ", c);
		}
	
	auto targets = doc["project"]["targets"].array;
	foreach(t; targets){
		writeln("targets found: ", t);
		}

	template wrapInException(string path){ //fixme bad name. Also. Not used anymore???
		import std.format;		
    	const char[] wrapInException = format("
			{
				try{
				
					foreach(string __path; dirEntries(FIXME ~ %s, \"*.d\", SpanMode.shallow.shallow)){   
					filesList ~= __path;
					}
				}catch(Exception e){
					writeln(\"Exception occured: \", e);
				}
			}", path);
		}
	writeln();

	globalConfig.automaticallyAddOutputExtension = doc["options"]["automaticallyAddOutputExtension"].boolean;

	string[] convTOMLtoArray(TOMLValue t){ 
		import std.algorithm : map;
		import std.array : array;
		return t.array.map!((o) => o.str).array;
		}

	string[] compilerNames = convTOMLtoArray(doc["project"]["compilers"]);
	foreach(m, n; doc["modeStrings"]){
		writeln("[",m, "] = ", n[0], "/", n[1], " of type ", n.type); // string
		modeStringConfig _modeString;
		foreach(i, t; n.array){_modeString.modePerCompiler[compilerNames[i]] ~= t.str;}
		globalConfig.modeStrings[m] = _modeString;
		}
	writeln(globalConfig);	

	foreach(t; targets){
		targetConfiguration tc;
		verboseWriteln("doc", t.str);
		auto d = doc[t.str];
		tc.target = t.str;

	//	foreach(value; d["sourcePaths"].array){cc.sourcePaths ~= value.str;}
		tc.sourcePaths 			= convTOMLtoArray(d["sourcePaths"]);
		tc.recursiveSourcePaths = convTOMLtoArray(d["recursiveSourcePaths"]);
		tc.libPaths 			= convTOMLtoArray(d["libPaths"]); 
		tc.recursiveLibPaths 	= convTOMLtoArray(d["recursiveLibPaths"]);
		tc.libs 				= convTOMLtoArray(d["libs"]);

		foreach(path; tc.sourcePaths){
				writefln("try scanning path %s for target %s", path, tc.target);
				try{				
					foreach(string __path; dirEntries(path, "*.d", SpanMode.shallow)){   
						writeln("\t", __path);
						tc.sourceFilesFound ~= __path;
						}
				}catch(Exception e){
					writeln("Exception occured: ", e);
				}
			}
		tConfigs[t.str] = tc;
		writeln("Source files found: ", tc.sourceFilesFound);
		}
	profileConfiguration[string] pConfigs;
	foreach(mode; doc["project"]["profiles"].array){
		string name = mode.str;
		writeln("Reading profile: ", name); // "debug", "release", etc
		
		auto buildProfileData = doc[mode.str];
		writeln("\t", buildProfileData);
		profileConfiguration pc;
		auto modeArray = buildProfileData["modesEnabled"].array; // selected modes for configuration
		string temp;
		string currentCompiler = "dmd"; // TODO FIXME.  compilerNames[i]?
		foreach(i, m; modeArray){
			writeln(i, m);
			writeln("\tfound mode ", m.str);
			temp ~= globalConfig.modeStrings[m.str].modePerCompiler[currentCompiler] ~ " ";
			}
		pc.mode = temp;
		writefln("\tfull mode string [%s]", temp);		
		pConfigs[name] = pc;
		}

	return pConfigs;
	}

void verboseWriteln(A...)(A a){  // todo: what about fln version. Pass in a std.format is all needed?
	if(exeConfig.doPrintVerbose){
		foreach(t; a)
			writeln(t);
		}
	}

struct exeConfigType{
	bool doCachedCompile = true;
	bool doRunCompiler = false;
	bool didCompileSucceed = false;
	bool doPrintVerbose = true; /// for error troubleshooting
	string modeSet="default"; // todo: change to enum or whatever. /// This is the builder mode state variable! NOT a "mode"/profile/etc. 'default' to start.
	
	string selectedProfile = "release";
	string selectedCompiler = "dmd";
	string selectedTargetOS = "";  // set by version statement in main.

	string buildScriptFileName = "buildConfig.toml"; /// Unless overriden with option TODO
	string cacheFileName = "buildFileCache.toml"; // should this be in the buildConfig?
	string extraCompilerFlags = "";
	string extraLinkerFlags = "";
	}

void displayHelp(){
	writeln("");
	writeln("  masterBuilder[.exe] [command] [option=value] [option=value] -- args");
	writeln("");
	writeln("\tinit  - create a default build config. TODO.");
	writeln("\trun   - run the program");
	writeln("\tbuild - actually build");
	writeln("\tclean - clean up temporary files");
	writeln("\tcheck - check if any files have changed and list them.");
	writeln("\ttry   - see if the build config would produce a compiler command");
	writeln("\tlint  - run DScanner");
	writeln("\tquote - recieve a verse about the Master Builder");
	writeln("\thelp  - this help screen.");
	writeln("");
	writeln("\tOptions:");
	writeln("\t\tprofile=name/of/profile (profile=release, profile=debug, etc)");
	writeln("\t\ttarget=windows/linux (Use commands for a different OS. Default: Your host OS.)");
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

bool isAny(string t, string v){ import std.string : indexOfAny; return (t.indexOfAny(v) != -1); } /// Is any string V in T? return: boolean

int parseModeBuild(string arg){
	import std.string : indexOfAny, toLower;

	writefln("parseModeBuild(%s)", arg);	
	immutable long n = arg.indexOfAny("=");
	if(n == -1){writeln("Missing equals?"); terminateEarlyString(arg); return -1;} // args must be in key=value, so if there's no equal it's invalid.
	writefln("matching [%s] = [%s]", arg[0..n], arg[n+1..$]);
	immutable string option=arg[0..n];
	immutable string value=arg[n+1..$];
	// note we ONLY change case of option! We don't want to
	//  accidentally change case of a compiler flag string!
	switch(option.toLower){
		case "profile":
			writeln("Setting profile=", value.toLower);
			exeConfig.selectedProfile = value.toLower;
			// look for profile names? We need to scan profiles before this?
			// or just let it rangeException out later.
			return 0;
		break;
		case "target":
			writeln("Setting target=", value.toLower);
			exeConfig.selectedTargetOS = value.toLower;
			return 0;
		break;
		case "compiler":
			writeln("Setting compiler=", value.toLower);
			exeConfig.selectedCompiler = value.toLower;
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

void commandClean(){
	} // TODO FIX ME BUG

void commandBuild(){
	profileConfiguration[string]  pConfigs = runToml();
	writeln(pConfigs);
    string filesList = "";

	writeln("");
	displayQuote();
	writeln("");
    writeln("Files to compile [", exeConfig.selectedTargetOS,"]");
	foreach(t; tConfigs){
		writeln(t.sourceFilesFound);
	}
	foreach(file; tConfigs[exeConfig.selectedTargetOS].sourceFilesFound){
		filesList ~= file ~ " ";
		}
	writefln("\"%s\"\n", filesList);

	auto fcl = new fileCacheList(tConfigs[exeConfig.selectedTargetOS].sourceFilesFound);
	string[] changedFiles = fcl.getDifferences();
	writeln("Changed files detected:");
	foreach(f; changedFiles){
		writeln("\t", f);
		}

    writeln("Library paths:");
	string libPathList = "";
	foreach(libpath; tConfigs[exeConfig.selectedTargetOS].libPaths){
		switch(tConfigs[exeConfig.selectedTargetOS].target){
			case("linux"):   libPathList ~= "-L-L"~libpath~" "; 		break;
			case("windows"): libPathList ~= "-L/LIBPATH:"~libpath~" ";	break;
			default:		 assert(0, format("invalid target name [%s]", exeConfig.selectedProfile)); break;
			}
		}
	writefln("\t\"%s\"", libPathList);

	writeln("");
	writefln("Buildname: %s (%s/%s)",	exeConfig.selectedProfile,
			exeConfig.selectedTargetOS, exeConfig.selectedCompiler);
	writeln("");

    immutable string flags = pConfigs[exeConfig.selectedProfile].mode;
	string runString;
	bool doCachedCompile=true;
	if(!doCachedCompile){
		runString =
			"dmd -of=" ~ pConfigs[exeConfig.selectedProfile].outputFilename ~ 
		  	" " ~ flags ~ " " ~	filesList ~ " " ~ libPathList ~ " " ~ 
			exeConfig.extraCompilerFlags ~ " " ~ exeConfig.extraLinkerFlags;
		
		if(exeConfig.doRunCompiler){
		auto dmd = executeShell(runString);
		if (dmd.status != 0){
			writeln("Compilation failed:\n", dmd.output);
			}else{
			writefln("Writing to [%s]", pConfigs[exeConfig.selectedProfile].outputFilename);
			writeln("Compilation succeeded:\n\n", dmd.output);
			writeln();
			exeConfig.didCompileSucceed = true;
			fcl.saveResults();
			}
		}else{
		writeln("Would have tried to execute the following string:");
		writeln("\t",runString);
		}
	}else{
		bool stopOnFirstError = true; /// do we stop on the first errored compile, or attempt all? exeConfig option?
		bool hasErrorOccurred = false; 
		foreach(file; changedFiles){
			string execString = format("dmd -c -od=/temp/ %s %s", file, libPathList);
			
			if(exeConfig.doRunCompiler){
				writeln("trying to execute:\n", execString);
				auto exec = executeShell(execString);				
				if(exec.status != 0){
					writefln("Compilation of %s failed:\n%s", file, exec.output);
					if(stopOnFirstError)break;
					}else{
					writefln("Compilation of %s succeeded.\n", file);
					}
				}else{
				writeln("Would have tried to execute (file to obj):\n\t", execString);
				}
			}
		if(hasErrorOccurred){writeln("Individual file compilation failed."); return;}
		// then if they all succeed, compile the final product.
		import std.string : replace;
		runString = "dmd -of=" ~ pConfigs[exeConfig.selectedProfile].outputFilename ~ 
		  	" " ~ flags ~ " " ~	filesList.replace(".d",".obj") ~ " " ~ libPathList ~ " " ~ 
			exeConfig.extraCompilerFlags ~ " " ~ exeConfig.extraLinkerFlags;

		if(!exeConfig.doRunCompiler){
			writeln("Would have tried to execute (executable):\n\t", runString);
			}else{
			writeln("Trying to execute:\n\t", runString);
			auto dmd = executeShell(runString);				
			if(dmd.status != 0){
				writefln("Compilation failed:\n%s", dmd.output);
				}else{
				writefln("Compilation succeeded.\n");
				}
			}
	}

	
	}

globalConfiguration globalConfig;
targetConfiguration[string] tConfigs;
exeConfigType exeConfig;

void setupDefaultOSstring(){
	exeConfig.selectedTargetOS = "excuse me, wat"; // default fail case.
	version(Windows)exeConfig.selectedTargetOS = "windows";
	version(Linux)exeConfig.selectedTargetOS   = "linux";
	version(MacOSX)exeConfig.selectedTargetOS  = "macos";
	}

int main(string[] args){
	setupDefaultOSstring();
	writeln(args);
	if(args.length > 1){
		parseCommandline(args[1..$]);
		}
    return 0;
	}
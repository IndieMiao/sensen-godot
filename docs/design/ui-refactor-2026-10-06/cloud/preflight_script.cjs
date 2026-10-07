// Syntax and pre-restore evaluation only; performs no Figma operations.
const fs=require('fs'),vm=require('vm');
(async()=>{
 const code=fs.readFileSync(process.argv[2],'utf8');
 const script=new vm.Script('(async()=>{'+code+'\n})()');
 try{await script.runInNewContext({figma:{getNodeByIdAsync(){throw Error('__CLOUD_RESTORE_BOUNDARY__')}},console,setTimeout},{timeout:5000});throw Error('No restore boundary reached');}
 catch(e){if(e.message!=='__CLOUD_RESTORE_BOUNDARY__')throw e;}
 console.log(JSON.stringify({file:process.argv[2],syntax:true,topLevelCaptures:true,figmaExecuted:false}));
})().catch(e=>{console.error(e.stack);process.exitCode=1});

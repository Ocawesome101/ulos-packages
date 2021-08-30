local ok,err=require("osgui")()
if not ok and err then io.stderr:write("osgui: ",err,"\n")os.exit(1)end

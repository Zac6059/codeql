**/Semmle.Extraction.CSharp.Driver:
  order compiler
  trace no
**/mcs.exe:
**/csc.exe:
  invoke ${config_dir}/../extract.sh
  prepend --compiler
  prepend "${compiler}"
  prepend --cil
**/mono*:
**/dotnet:
  invoke ${config_dir}/../extract-preload.sh

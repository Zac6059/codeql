import javascript
import semmle.javascript.security.dataflow.Xss
import semmle.javascript.security.dataflow.CodeInjectionCustomizations

query Templating::TemplateSyntax getTemplateInstantiationSyntax(
  Templating::TemplateInstantiaton inst
) {
  result = inst.getTemplateSyntax()
}

query Templating::TemplateSyntax getLikelyTemplateSyntax(Templating::TemplateFile file) {
  result = Templating::getLikelyTemplateSyntax(file)
}

query Templating::TemplateFile getTargetFile(Templating::TemplateInstantiaton inst) {
  result = inst.getTemplateFile()
}

query DomBasedXss::Sink xssSink() { any() }

query CodeInjection::Sink codeInjectionSink() { any() }

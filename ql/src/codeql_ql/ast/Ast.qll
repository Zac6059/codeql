import ql
private import codeql_ql.ast.internal.AstNodes
private import codeql_ql.ast.internal.Module
private import codeql_ql.ast.internal.Predicate
import codeql_ql.ast.internal.Type
private import codeql_ql.ast.internal.Variable

bindingset[name]
private string directMember(string name) { result = name + "()" }

bindingset[name, i]
private string indexedMember(string name, int i) { result = name + "(_)" }

bindingset[name, index]
private string stringIndexedMember(string name, string index) { result = name + "(_)" }

/** An AST node of a QL program */
class AstNode extends TAstNode {
  string toString() { result = getAPrimaryQlClass() }

  Location getLocation() {
    exists(Generated::AstNode node | not node instanceof Generated::ParExpr |
      node = toGenerated(this) and
      result = node.getLocation()
    )
  }

  AstNode getParent() { result.getAChild(_) = this }

  /**
   * Gets a child of this node, which can also be retrieved using a predicate
   * named `pred`.
   */
  cached
  AstNode getAChild(string pred) { none() }

  string getAPrimaryQlClass() { result = "???" }
}

class TopLevel extends TTopLevel, AstNode {
  Generated::Ql file;

  TopLevel() { this = TTopLevel(file) }

  ModuleMember getAMember() { toGenerated(result) = file.getChild(_).getChild(_) }

  override ModuleMember getAChild(string pred) {
    pred = directMember("getAMember") and result = this.getAMember()
  }

  override string getAPrimaryQlClass() { result = "TopLevel" }
}

/**
 * The `from, where, select` part of a QL query.
 */
class Select extends TSelect, AstNode {
  Generated::Select sel;

  Select() { this = TSelect(sel) }

  VarDecl getVarDecl(int i) { toGenerated(result) = sel.getChild(i) }

  Formula getWhere() { toGenerated(result) = sel.getChild(_) }

  Expr getExpr(int i) { toGenerated(result) = sel.getChild(_).(Generated::AsExprs).getChild(i) }

  Expr getOrderBy(int i) {
    toGenerated(result) = sel.getChild(_).(Generated::OrderBys).getChild(i).getChild(0)
  }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getWhere") and result = this.getWhere()
    or
    exists(int i |
      pred = indexedMember("getVarDecl", i) and result = this.getVarDecl(i)
      or
      pred = indexedMember("getExpr", i) and result = this.getExpr(i)
      or
      pred = indexedMember("getOrderBy", i) and result = this.getOrderBy(i)
    )
  }

  override string getAPrimaryQlClass() { result = "Select" }
}

/**
 * A QL predicate.
 */
class Predicate extends TPredicate, AstNode {
  /**
   * Gets the body of the predicate.
   */
  Formula getBody() { none() }

  /**
   * Gets the name of the predicate.
   */
  string getName() { none() }

  /**
   * Gets the `i`th parameter of the predicate.
   */
  VarDecl getParameter(int i) { none() }

  int getArity() { result = count(getParameter(_)) }

  /**
   * Gets the return type (if any) of the predicate.
   */
  TypeExpr getReturnType() { none() }

  // TODO: ReturnType.
  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getBody") and result = this.getBody()
    or
    exists(int i | pred = indexedMember("getParameter", i) and result = this.getParameter(i))
    or
    pred = directMember("getReturnType") and result = this.getReturnType()
  }

  override string getAPrimaryQlClass() { result = "Predicate" }
}

class PredicateExpr extends TPredicateExpr, AstNode {
  Generated::PredicateExpr pe;

  PredicateExpr() { this = TPredicateExpr(pe) }

  override string toString() { result = "predicate" }

  string getName() {
    exists(Generated::AritylessPredicateExpr ape, Generated::LiteralId id |
      ape.getParent() = pe and
      id.getParent() = ape and
      result = id.getValue()
    )
  }

  int getArity() {
    exists(Generated::Integer i |
      i.getParent() = pe and
      result = i.getValue().toInt()
    )
  }

  ModuleExpr getQualifier() {
    exists(Generated::AritylessPredicateExpr ape |
      ape.getParent() = pe and
      toGenerated(result).getParent() = ape
    )
  }

  Predicate getResolvedPredicate() { resolvePredicateExpr(this, result) }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getQualifier") and result = this.getQualifier()
  }

  override string getAPrimaryQlClass() { result = "PredicateExpr" }
}

/**
 * A classless predicate.
 */
class ClasslessPredicate extends TClasslessPredicate, Predicate, ModuleDeclaration {
  Generated::ModuleMember member;
  Generated::ClasslessPredicate pred;

  ClasslessPredicate() { this = TClasslessPredicate(member, pred) }

  final AstNode getAlias() {
    exists(Generated::PredicateAliasBody alias |
      alias.getParent() = pred and
      toGenerated(result).getParent() = alias
    )
    or
    toGenerated(result) = pred.getChild(_).(Generated::HigherOrderTerm)
  }

  final override predicate isPrivate() {
    member.getAFieldOrChild().(Generated::Annotation).getName().getValue() = "private"
  }

  override string getAPrimaryQlClass() { result = "ClasslessPredicate" }

  override Formula getBody() { toGenerated(result) = pred.getChild(_).(Generated::Body).getChild() }

  override string getName() { result = pred.getName().getValue() }

  override VarDecl getParameter(int i) {
    toGenerated(result) =
      rank[i](Generated::VarDecl decl, int index | decl = pred.getChild(index) | decl order by index)
  }

  override TypeExpr getReturnType() { toGenerated(result) = pred.getReturnType() }

  override AstNode getAChild(string pred_name) {
    result = Predicate.super.getAChild(pred_name)
    or
    pred_name = directMember("getAlias") and result = this.getAlias()
    or
    pred_name = directMember("getBody") and result = this.getBody()
    or
    exists(int i | pred_name = indexedMember("getParameter", i) and result = this.getParameter(i))
    or
    pred_name = directMember("getReturnType") and result = this.getReturnType()
  }
}

/**
 * A predicate in a class.
 */
class ClassPredicate extends TClassPredicate, Predicate {
  Generated::MemberPredicate pred;

  ClassPredicate() { this = TClassPredicate(pred) }

  override string getName() { result = pred.getName().getValue() }

  override Formula getBody() { toGenerated(result) = pred.getChild(_).(Generated::Body).getChild() }

  override string getAPrimaryQlClass() { result = "ClassPredicate" }

  override Class getParent() { result.getAClassPredicate() = this }

  predicate isPrivate() { hasAnnotation("private") }

  predicate hasAnnotation(string name) {
    exists(Generated::ClassMember member |
      pred = member.getChild(_) and
      member.getAFieldOrChild().(Generated::Annotation).getName().getValue() = name
    )
  }

  override VarDecl getParameter(int i) {
    toGenerated(result) =
      rank[i](Generated::VarDecl decl, int index | decl = pred.getChild(index) | decl order by index)
  }

  ClassType getDeclaringType() { result.getDeclaration() = getParent() }

  predicate overrides(ClassPredicate other) { predOverrides(this, other) }

  override TypeExpr getReturnType() { toGenerated(result) = pred.getReturnType() }

  override AstNode getAChild(string pred_name) {
    result = super.getAChild(pred_name)
    or
    pred_name = directMember("getBody") and result = this.getBody()
    or
    exists(int i | pred_name = indexedMember("getParameter", i) and result = this.getParameter(i))
    or
    pred_name = directMember("getReturnType") and result = this.getReturnType()
  }
}

/**
 * A characteristic predicate of a class.
 */
class CharPred extends TCharPred, Predicate {
  Generated::Charpred pred;

  CharPred() { this = TCharPred(pred) }

  override string getAPrimaryQlClass() { result = "CharPred" }

  override Formula getBody() { toGenerated(result) = pred.getBody() }

  override string getName() { result = getParent().(Class).getName() }

  override AstNode getAChild(string pred_name) {
    result = super.getAChild(pred_name)
    or
    pred_name = directMember("getBody") and result = this.getBody()
  }
}

/**
 * A variable definition. This is either a variable declaration or
 * an `as` expression.
 */
class VarDef extends TVarDef, AstNode {
  /** Gets the name of the declared variable. */
  string getName() { none() }

  override string getAPrimaryQlClass() { result = "VarDef" }

  override string toString() { result = this.getName() }
}

/**
 * A variable declaration, with a type and a name.
 */
class VarDecl extends TVarDecl, VarDef {
  Generated::VarDecl var;

  VarDecl() { this = TVarDecl(var) }

  override string getName() { result = var.getChild(1).(Generated::VarName).getChild().getValue() }

  override string getAPrimaryQlClass() { result = "VarDecl" }

  TypeExpr getType() { toGenerated(result) = var.getChild(0) }

  predicate isPrivate() {
    exists(Generated::ClassMember member |
      var = member.getChild(_).(Generated::Field).getChild() and
      member.getAFieldOrChild().(Generated::Annotation).getName().getValue() = "private"
    )
  }

  /** If this is a field, returns the class type that declares it. */
  ClassType getDeclaringType() { result.getDeclaration().getAField() = this }

  predicate overrides(VarDecl other) { fieldOverrides(this, other) }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getType") and result = this.getType()
  }
}

/**
 * A type reference, such as `DataFlow::Node`.
 */
class TypeExpr extends TType, AstNode {
  Generated::TypeExpr type;

  TypeExpr() { this = TType(type) }

  override string getAPrimaryQlClass() { result = "TypeExpr" }

  /**
   * Gets the class name for the type.
   * E.g. `Node` in `DataFlow::Node`.
   * Also gets the name for primitive types such as `string` or `int`
   * or db-types such as `@locateable`.
   */
  string getClassName() {
    result = type.getName().getValue()
    or
    result = type.getChild().(Generated::PrimitiveType).getValue()
    or
    result = type.getChild().(Generated::Dbtype).getValue()
  }

  /**
   * Holds if this type is a primitive such as `string` or `int`.
   */
  predicate isPrimitive() { type.getChild() instanceof Generated::PrimitiveType }

  /**
   * Holds if this type is a db-type.
   */
  predicate isDBType() { type.getChild() instanceof Generated::Dbtype }

  /**
   * Gets the module of the type, if it exists.
   * E.g. `DataFlow` in `DataFlow::Node`.
   */
  ModuleExpr getModule() { toGenerated(result) = type.getChild() }

  Type getResolvedType() { resolveTypeExpr(this, result) }

  override ModuleExpr getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getModule") and result = this.getModule()
  }
}

/**
 * A QL module.
 */
class Module extends TModule, ModuleDeclaration {
  Generated::Module mod;

  Module() { this = TModule(mod) }

  override string getAPrimaryQlClass() { result = "Module" }

  final override predicate isPrivate() {
    exists(Generated::ModuleMember member |
      mod = member.getChild(_) and
      member.getAFieldOrChild().(Generated::Annotation).getName().getValue() = "private"
    )
  }

  override string getName() { result = mod.getName().(Generated::ModuleName).getChild().getValue() }

  /**
   * Gets a member of the module.
   */
  AstNode getAMember() {
    toGenerated(result) = mod.getChild(_).(Generated::ModuleMember).getChild(_)
  }

  /** Gets the module expression that this module is an alias for, if any. */
  ModuleExpr getAlias() {
    toGenerated(result) = mod.getAFieldOrChild().(Generated::ModuleAliasBody).getChild()
  }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getAlias") and result = this.getAlias()
    or
    pred = directMember("getAMember") and result = this.getAMember()
  }
}

/**
 * Something that can be member of a module.
 */
class ModuleMember extends TModuleMember, AstNode {
  /** Holds if this member is declared as `private`. */
  predicate isPrivate() { none() } // TODO: Implement.
}

/** A declaration. */
class Declaration extends TDeclaration, AstNode {
  /** Gets the name of this declaration. */
  string getName() { none() }

  final override string toString() { result = this.getName() }
}

/** An entity that can be declared in a module. */
class ModuleDeclaration extends TModuleDeclaration, Declaration, ModuleMember { }

/** An type declaration. Either a `class` or a `newtype`. */
class TypeDeclaration extends TTypeDeclaration, Declaration { }

/**
 * A QL class.
 */
class Class extends TClass, TypeDeclaration, ModuleDeclaration {
  Generated::Dataclass cls;

  Class() { this = TClass(cls) }

  override string getAPrimaryQlClass() { result = "Class" }

  final override predicate isPrivate() {
    exists(Generated::ModuleMember member |
      cls = member.getChild(_) and
      member.getAFieldOrChild().(Generated::Annotation).getName().getValue() = "private"
    )
  }

  override string getName() { result = cls.getName().getValue() }

  /**
   * Gets the charateristic predicate for this class.
   */
  CharPred getCharPred() {
    toGenerated(result) = cls.getChild(_).(Generated::ClassMember).getChild(_)
  }

  /**
   * Gets a predicate in this class.
   */
  ClassPredicate getAClassPredicate() {
    toGenerated(result) = cls.getChild(_).(Generated::ClassMember).getChild(_)
  }

  /**
   * Gets predicate `name` implemented in this class.
   */
  ClassPredicate getClassPredicate(string name) {
    result = getAClassPredicate() and
    result.getName() = name
  }

  /**
   * Gets a field in this class.
   */
  VarDecl getAField() {
    toGenerated(result) =
      cls.getChild(_).(Generated::ClassMember).getChild(_).(Generated::Field).getChild()
  }

  TypeExpr getASuperType() { toGenerated(result) = cls.getChild(_) }

  /** Gets the type that this class is defined to be an alias of. */
  TypeExpr getAliasType() {
    toGenerated(result) = cls.getChild(_).(Generated::TypeAliasBody).getChild()
  }

  /** Gets the type of one of the members that this class is defined to be a union of. */
  TypeExpr getUnionMember() {
    toGenerated(result) = cls.getChild(_).(Generated::TypeUnionBody).getChild(_)
  }

  /** Gets the class type defined by this class declaration. */
  Type getType() { result.getDeclaration() = this }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getAliasType") and result = this.getAliasType()
    or
    pred = directMember("getUnionMember") and result = this.getUnionMember()
    or
    pred = directMember("getAField") and result = this.getAField()
    or
    pred = directMember("getCharPred") and result = this.getCharPred()
    or
    pred = directMember("getASuperType") and result = this.getASuperType()
    or
    exists(string name |
      pred = stringIndexedMember("getClassPredicate", name) and
      result = this.getClassPredicate(name)
    )
  }
}

/**
 * A `newtype Foo` declaration.
 */
class NewType extends TNewType, TypeDeclaration, ModuleDeclaration {
  Generated::Datatype type;

  NewType() { this = TNewType(type) }

  override string getName() { result = type.getName().getValue() }

  override string getAPrimaryQlClass() { result = "NewType" }

  final override predicate isPrivate() {
    exists(Generated::ModuleMember member |
      type = member.getChild(_) and
      member.getAFieldOrChild().(Generated::Annotation).getName().getValue() = "private"
    )
  }

  /**
   * Gets a branch in this `newtype`.
   */
  NewTypeBranch getABranch() { toGenerated(result) = type.getChild().getChild(_) }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getABranch") and result = this.getABranch()
  }
}

/**
 * A branch in a `newtype`.
 */
class NewTypeBranch extends TNewTypeBranch, TypeDeclaration {
  Generated::DatatypeBranch branch;

  NewTypeBranch() { this = TNewTypeBranch(branch) }

  override string getAPrimaryQlClass() { result = "NewTypeBranch" }

  override string getName() { result = branch.getName().getValue() }

  /** Gets a field in this branch. */
  VarDecl getField(int i) {
    toGenerated(result) =
      rank[i + 1](Generated::VarDecl var, int index |
        var = branch.getChild(index)
      |
        var order by index
      )
  }

  /** Gets the body of this branch. */
  Formula getBody() { toGenerated(result) = branch.getChild(_).(Generated::Body).getChild() }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getBody") and result = this.getBody()
    or
    exists(int i | pred = indexedMember("getField", i) and result = this.getField(i))
  }
}

class Call extends TCall, AstNode {
  Expr getArgument(int i) {
    none() // overriden in sublcasses.
  }

  ModuleExpr getQualifier() { none() }
}

class PredicateCall extends TPredicateCall, Call {
  Generated::CallOrUnqualAggExpr expr;

  PredicateCall() { this = TPredicateCall(expr) }

  override Expr getArgument(int i) {
    exists(Generated::CallBody body | body.getParent() = expr |
      toGenerated(result) = body.getChild(i)
    )
  }

  final override ModuleExpr getQualifier() {
    exists(Generated::AritylessPredicateExpr ape |
      ape.getParent() = expr and
      toGenerated(result).getParent() = ape
    )
  }

  override string getAPrimaryQlClass() { result = "PredicateCall" }

  string getPredicateName() {
    result = expr.getChild(0).(Generated::AritylessPredicateExpr).getName().getValue()
  }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    exists(int i | pred = indexedMember("getArgument", i) and result = this.getArgument(i))
    or
    pred = directMember("getQualifier") and result = this.getQualifier()
  }
}

class MemberCall extends TMemberCall, Call {
  Generated::QualifiedExpr expr;

  MemberCall() { this = TMemberCall(expr) }

  override string getAPrimaryQlClass() { result = "MemberCall" }

  string getMemberName() {
    result = expr.getChild(_).(Generated::QualifiedRhs).getName().getValue()
  }

  /**
   * Gets the supertype referenced in this call, that is the `Foo` in `Foo.super.bar(...)`.
   *
   * Only yields a result if this is actually a `super` call.
   */
  TypeExpr getSuperType() {
    toGenerated(result) = expr.getChild(_).(Generated::SuperRef).getChild(0)
  }

  override Expr getArgument(int i) {
    result =
      rank[i + 1](Expr e, int index |
        toGenerated(e) = expr.getChild(_).(Generated::QualifiedRhs).getChild(index)
      |
        e order by index
      )
  }

  Expr getBase() { toGenerated(result) = expr.getChild(0) }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getBase") and result = this.getBase()
    or
    pred = directMember("getSuperType") and result = this.getSuperType()
    or
    exists(int i | pred = indexedMember("getArgument", i) and result = this.getArgument(i))
  }
}

class NoneCall extends TNoneCall, Call, Formula {
  Generated::SpecialCall call;

  NoneCall() { this = TNoneCall(call) }

  override string getAPrimaryQlClass() { result = "NoneCall" }
}

class AnyCall extends TAnyCall, Call {
  Generated::Aggregate agg;

  AnyCall() { this = TAnyCall(agg) }

  override string getAPrimaryQlClass() { result = "AnyCall" }
}

class InlineCast extends TInlineCast, Expr {
  Generated::QualifiedExpr expr;

  InlineCast() { this = TInlineCast(expr) }

  override string getAPrimaryQlClass() { result = "InlineCast" }

  TypeExpr getType() {
    toGenerated(result) = expr.getChild(_).(Generated::QualifiedRhs).getChild(_)
  }

  Expr getBase() { toGenerated(result) = expr.getChild(0) }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getType") and result = this.getType()
    or
    pred = directMember("getBase") and result = this.getBase()
  }
}

/** An entity that resolves to a module. */
class ModuleRef extends AstNode, TModuleRef {
  /** Gets the module that this entity resolves to. */
  FileOrModule getResolvedModule() { none() }
}

/**
 * An import statement.
 */
class Import extends TImport, ModuleMember, ModuleRef {
  Generated::ImportDirective imp;

  Import() { this = TImport(imp) }

  override string getAPrimaryQlClass() { result = "Import" }

  /**
   * Gets the name under which this import is imported, if such a name exists.
   * E.g. the `Flow` in:
   * ```
   * import semmle.javascript.dataflow.Configuration as Flow
   * ```
   */
  string importedAs() { result = imp.getChild(1).(Generated::ModuleName).getChild().getValue() }

  /**
   * Gets the `i`th selected name from the imported module.
   * E.g. for
   * `import foo.bar::Baz::Qux`
   * It is true that `getSelectionName(0) = "Baz"` and `getSelectionName(1) = "Qux"`.
   */
  string getSelectionName(int i) {
    result = imp.getChild(0).(Generated::ImportModuleExpr).getName(i).getValue()
  }

  /**
   * Gets the `i`th imported module.
   * E.g. for
   * `import foo.bar::Baz::Qux`
   * It is true that `getQualifiedName(0) = "foo"` and `getQualifiedName(1) = "bar"`.
   */
  string getQualifiedName(int i) {
    result = imp.getChild(0).(Generated::ImportModuleExpr).getChild().getName(i).getValue()
  }

  final override predicate isPrivate() {
    exists(Generated::ModuleMember member |
      imp = member.getChild(_) and
      member.getAFieldOrChild().(Generated::Annotation).getName().getValue() = "private"
    )
  }

  final override FileOrModule getResolvedModule() { resolve(this, result) }
}

/** A formula, such as `x = 6 and y < 5`. */
class Formula extends TFormula, AstNode { }

/** An `and` formula, with 2 or more operands. */
class Conjunction extends TConjunction, AstNode, Formula {
  Generated::Conjunction conj;

  Conjunction() { this = TConjunction(conj) }

  override string getAPrimaryQlClass() { result = "Conjunction" }

  /** Gets an operand to this formula. */
  Formula getAnOperand() { toGenerated(result) in [conj.getLeft(), conj.getRight()] }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getAnOperand") and result = this.getAnOperand()
  }
}

/** An `or` formula, with 2 or more operands. */
class Disjunction extends TDisjunction, AstNode {
  Generated::Disjunction disj;

  Disjunction() { this = TDisjunction(disj) }

  override string getAPrimaryQlClass() { result = "Disjunction" }

  /** Gets an operand to this formula. */
  Formula getAnOperand() { toGenerated(result) in [disj.getLeft(), disj.getRight()] }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getAnOperand") and result = this.getAnOperand()
  }
}

/**
 * A comparison operator, such as `<` or `=`.
 */
class ComparisonOp extends TComparisonOp, AstNode {
  Generated::Compop op;

  ComparisonOp() { this = TComparisonOp(op) }

  ComparisonSymbol getSymbol() { result = op.getValue() }

  override string getAPrimaryQlClass() { result = "ComparisonOp" }
}

/**
 * A literal expression, such as `6` or `true` or `"foo"`.
 */
class Literal extends TLiteral, Expr {
  Generated::Literal lit;

  Literal() { this = TLiteral(lit) }

  override string getAPrimaryQlClass() { result = "??Literal??" }
}

/** A string literal. */
class String extends Literal {
  String() { lit.getChild() instanceof Generated::String }

  override string getAPrimaryQlClass() { result = "String" }

  /** Gets the string value of this literal. */
  string getValue() {
    exists(string raw | raw = lit.getChild().(Generated::String).getValue() |
      result = raw.substring(1, raw.length() - 1)
    )
  }
}

/** An integer literal. */
class Integer extends Literal {
  Integer() { lit.getChild() instanceof Generated::Integer }

  override string getAPrimaryQlClass() { result = "Integer" }

  /** Gets the integer value of this literal. */
  int getValue() { result = lit.getChild().(Generated::Integer).getValue().toInt() }
}

/** A comparison symbol, such as `"<"` or `"="`. */
class ComparisonSymbol extends string {
  ComparisonSymbol() {
    this = "=" or
    this = "!=" or
    this = "<" or
    this = ">" or
    this = "<=" or
    this = ">="
  }
}

/** A comparison formula, such as `x < 3` or `y = true`. */
class ComparisonFormula extends TComparisonFormula, Formula {
  Generated::CompTerm comp;

  ComparisonFormula() { this = TComparisonFormula(comp) }

  /** Gets the left operand of this comparison. */
  Expr getLeftOperand() { toGenerated(result) = comp.getLeft() }

  /** Gets the right operand of this comparison. */
  Expr getRightOperand() { toGenerated(result) = comp.getRight() }

  /** Gets an operand of this comparison. */
  Expr getAnOperand() { result in [getLeftOperand(), getRightOperand()] }

  /** Gets the operator of this comparison. */
  ComparisonOp getOperator() { toGenerated(result) = comp.getChild() }

  /** Gets the symbol of this comparison (as a string). */
  ComparisonSymbol getSymbol() { result = this.getOperator().getSymbol() }

  override string getAPrimaryQlClass() { result = "ComparisonFormula" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getLeftOperand") and result = this.getLeftOperand()
    or
    pred = directMember("getRightOperand") and result = this.getRightOperand()
    or
    pred = directMember("getOperator") and result = this.getOperator()
  }
}

/** A quantifier formula, such as `exists` or `forall`. */
class Quantifier extends TQuantifier, Formula {
  Generated::Quantified quant;
  string kind;

  Quantifier() {
    this = TQuantifier(quant) and kind = quant.getChild(0).(Generated::Quantifier).getValue()
  }

  /** Gets the ith variable declaration of this quantifier. */
  VarDecl getArgument(int i) {
    i >= 1 and
    toGenerated(result) = quant.getChild(i - 1)
  }

  /** Gets an argument of this quantifier. */
  VarDecl getAnArgument() { result = this.getArgument(_) }

  /** Gets the formula restricting the range of this quantifier, if any. */
  Formula getRange() { toGenerated(result) = quant.getRange() }

  /** Holds if this quantifier has a range formula. */
  predicate hasRange() { exists(this.getRange()) }

  /** Gets the main body of the quantifier. */
  Formula getFormula() { toGenerated(result) = quant.getFormula() }

  /**
   * Gets the expression of this quantifier, if the quantifier is
   * of the form `exists( expr )`.
   */
  Expr getExpr() { toGenerated(result) = quant.getExpr() }

  /**
   * Holds if this is the "expression only" form of an exists quantifier.
   * In other words, the quantifier is of the form `exists( expr )`.
   */
  predicate hasExpr() { exists(getExpr()) }

  override string getAPrimaryQlClass() { result = "Quantifier" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    exists(int i | pred = indexedMember("getArgument", i) and result = this.getArgument(i))
    or
    pred = directMember("getRange") and result = this.getRange()
    or
    pred = directMember("getFormula") and result = this.getFormula()
    or
    pred = directMember("getExpr") and result = this.getExpr()
  }
}

/** An `exists` quantifier. */
class Exists extends Quantifier {
  Exists() { kind = "exists" }

  override string getAPrimaryQlClass() { result = "Exists" }
}

/** A `forall` quantifier. */
class Forall extends Quantifier {
  Forall() { kind = "forall" }

  override string getAPrimaryQlClass() { result = "Forall" }
}

/** A `forex` quantifier. */
class Forex extends Quantifier {
  Forex() { kind = "forex" }

  override string getAPrimaryQlClass() { result = "Forex" }
}

/** A conditional formula, of the form  `if a then b else c`. */
class IfFormula extends TIfFormula, Formula {
  Generated::IfTerm ifterm;

  IfFormula() { this = TIfFormula(ifterm) }

  /** Gets the condition (the `if` part) of this formula. */
  Formula getCondition() { toGenerated(result) = ifterm.getCond() }

  /** Gets the `then` part of this formula. */
  Formula getThenPart() { toGenerated(result) = ifterm.getFirst() }

  /** Gets the `else` part of this formula. */
  Formula getElsePart() { toGenerated(result) = ifterm.getSecond() }

  override string getAPrimaryQlClass() { result = "IfFormula" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getCondition") and result = this.getCondition()
    or
    pred = directMember("getThenPart") and result = this.getThenPart()
    or
    pred = directMember("getElsePart") and result = this.getElsePart()
  }
}

/**
 * An implication formula, of the form `foo implies bar`.
 */
class Implication extends TImplication, Formula {
  Generated::Implication imp;

  Implication() { this = TImplication(imp) }

  /** Gets the left operand of this implication. */
  Formula getLeftOperand() { toGenerated(result) = imp.getLeft() }

  /** Gets the right operand of this implication. */
  Formula getRightOperand() { toGenerated(result) = imp.getRight() }

  override string getAPrimaryQlClass() { result = "Implication" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getLeftOperand") and result = this.getLeftOperand()
    or
    pred = directMember("getRightOperand") and result = this.getRightOperand()
  }
}

/**
 * A type check formula, of the form `foo instanceof bar`.
 */
class InstanceOf extends TInstanceOf, Formula {
  Generated::InstanceOf inst;

  InstanceOf() { this = TInstanceOf(inst) }

  /** Gets the expression being checked. */
  Expr getExpr() { toGenerated(result) = inst.getChild(0) }

  /** Gets the reference to the type being checked. */
  TypeExpr getType() { toGenerated(result) = inst.getChild(1) }

  /** Gets the type being checked. */
  //QLTypeExpr getType() { result = getTypeRef().getType() }
  override string getAPrimaryQlClass() { result = "InstanceOf" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getExpr") and result = this.getExpr()
    or
    pred = directMember("getType") and result = this.getType()
  }
}

class InFormula extends TInFormula, Formula {
  Generated::InExpr inexpr;

  InFormula() { this = TInFormula(inexpr) }

  Expr getExpr() { toGenerated(result) = inexpr.getLeft() }

  Expr getRange() { toGenerated(result) = inexpr.getRight() }

  override string getAPrimaryQlClass() { result = "InFormula" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getExpr") and result = this.getExpr()
    or
    pred = directMember("getRange") and result = this.getRange()
  }
}

class HigherOrderFormula extends THigherOrderFormula, Formula {
  Generated::HigherOrderTerm hop;

  HigherOrderFormula() { this = THigherOrderFormula(hop) }

  PredicateExpr getInput(int i) { toGenerated(result) = hop.getChild(i).(Generated::PredicateExpr) }

  private int getNumInputs() { result = 1 + max(int i | exists(this.getInput(i))) }

  Expr getArgument(int i) { toGenerated(result) = hop.getChild(i + getNumInputs()) }

  string getName() { result = hop.getName().getValue() }

  override string getAPrimaryQlClass() { result = "HigherOrderFormula" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    exists(int i |
      pred = indexedMember("getInput", i) and result = this.getInput(i)
      or
      pred = indexedMember("getArgument", i) and result = this.getArgument(i)
    )
  }
}

class ExprAggregate extends TExprAggregate, Expr {
  Generated::Aggregate agg;
  Generated::ExprAggregateBody body;
  string kind;

  ExprAggregate() {
    this = TExprAggregate(agg) and
    kind = agg.getChild(0).(Generated::AggId).getValue() and
    body = agg.getChild(_)
  }

  string getKind() { result = kind }

  /**
   * Gets the ith "as" expression of this aggregate, if any.
   */
  Expr getExpr(int i) { toGenerated(result) = body.getAsExprs().getChild(i) }

  /**
   * Gets the ith "order by" expression of this aggregate, if any.
   */
  Expr getOrderBy(int i) { toGenerated(result) = body.getOrderBys().getChild(i).getChild(0) }

  /**
   * Gets the direction (ascending or descending) of the ith "order by" expression of this aggregate.
   */
  string getOrderbyDirection(int i) {
    result = body.getOrderBys().getChild(i).getChild(1).(Generated::Direction).getValue()
  }

  override string getAPrimaryQlClass() { result = "ExprAggregate[" + kind + "]" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    exists(int i |
      pred = indexedMember("getExpr", i) and result = this.getExpr(i)
      or
      pred = indexedMember("getOrderBy", i) and result = this.getOrderBy(i)
    )
  }
}

/** An aggregate expression, such as `count` or `sum`. */
class Aggregate extends TAggregate, Expr {
  Generated::Aggregate agg;
  string kind;
  Generated::FullAggregateBody body;

  Aggregate() {
    this = TAggregate(agg) and
    kind = agg.getChild(0).(Generated::AggId).getValue() and
    body = agg.getChild(_)
  }

  string getKind() { result = kind }

  /** Gets the ith declared argument of this quantifier. */
  VarDecl getArgument(int i) { toGenerated(result) = body.getChild(i) }

  /** Gets an argument of this quantifier. */
  VarDecl getAnArgument() { result = this.getArgument(_) }

  /**
   * Gets the formula restricting the range of this quantifier, if any.
   */
  Formula getRange() { toGenerated(result) = body.getGuard() }

  /**
   * Gets the ith "as" expression of this aggregate, if any.
   */
  Expr getExpr(int i) { toGenerated(result) = body.getAsExprs().getChild(i) }

  /**
   * Gets the ith "order by" expression of this aggregate, if any.
   */
  Expr getOrderBy(int i) { toGenerated(result) = body.getOrderBys().getChild(i).getChild(0) }

  /**
   * Gets the direction (ascending or descending) of the ith "order by" expression of this aggregate.
   */
  string getOrderbyDirection(int i) {
    result = body.getOrderBys().getChild(i).getChild(1).(Generated::Direction).getValue()
  }

  override string getAPrimaryQlClass() { result = "Aggregate[" + kind + "]" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    exists(int i |
      pred = indexedMember("getArgument", i) and result = this.getArgument(i)
      or
      pred = indexedMember("getExpr", i) and result = this.getExpr(i)
      or
      pred = indexedMember("getOrderBy", i) and result = this.getOrderBy(i)
    )
    or
    pred = directMember("getRange") and result = this.getRange()
  }
}

/**
 * A "rank" expression, such as `rank[4](int i | i = [5 .. 15] | i)`.
 */
class Rank extends Aggregate {
  Rank() { kind = "rank" }

  override string getAPrimaryQlClass() { result = "Rank" }

  /**
   * The `i` in `rank[i]( | | )`.
   */
  Expr getRankExpr() { toGenerated(result) = agg.getChild(1) }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getRankExpr") and result = this.getRankExpr()
  }
}

/**
 * An "as" expression, such as `foo as bar`.
 */
class AsExpr extends TAsExpr, VarDef, Expr {
  Generated::AsExpr asExpr;

  AsExpr() { this = TAsExpr(asExpr) }

  override string getAPrimaryQlClass() { result = "AsExpr" }

  final override string getName() { result = this.getAsName() }

  /**
   * Gets the name the inner expression gets "saved" under.
   * For example this is `bar` in the expression `foo as bar`.
   */
  string getAsName() { result = asExpr.getChild(1).(Generated::VarName).getChild().getValue() }

  /**
   * Gets the inner expression of the "as" expression. For example, this is `foo` in
   * the expression `foo as bar`.
   */
  Expr getInnerExpr() { toGenerated(result) = asExpr.getChild(0) }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getInnerExpr") and result = this.getInnerExpr()
  }
}

class Identifier extends TIdentifier, Expr {
  Generated::Variable id;

  Identifier() { this = TIdentifier(id) }

  string getName() { none() }

  final override string toString() { result = this.getName() }

  override string getAPrimaryQlClass() { result = "Identifier" }
}

/** An access to a variable. */
class VarAccess extends Identifier {
  private VarDef decl;

  VarAccess() { resolveVariable(this, decl) }

  /** Gets the accessed variable. */
  VarDef getDeclaration() { result = decl }

  override string getName() { result = id.getChild().(Generated::VarName).getChild().getValue() }

  override string getAPrimaryQlClass() { result = "VarAccess" }
}

/** An access to a field. */
class FieldAccess extends Identifier {
  private VarDecl decl;

  FieldAccess() { resolveField(this, decl) }

  /** Gets the accessed field. */
  VarDecl getDeclaration() { result = decl }

  override string getName() { result = id.getChild().(Generated::VarName).getChild().getValue() }

  override string getAPrimaryQlClass() { result = "FieldAccess" }
}

/** An access to `this`. */
class ThisAccess extends Identifier {
  ThisAccess() { any(Generated::This t).getParent() = id }

  override string getName() { result = "this" }

  override string getAPrimaryQlClass() { result = "ThisAccess" }
}

/** An access to `result`. */
class ResultAccess extends Identifier {
  ResultAccess() { any(Generated::Result r).getParent() = id }

  override string getName() { result = "result" }

  override string getAPrimaryQlClass() { result = "ResultAccess" }
}

/** A `not` formula. */
class Negation extends TNegation, Formula {
  Generated::Negation neg;

  Negation() { this = TNegation(neg) }

  /** Gets the formula being negated. */
  Formula getFormula() { toGenerated(result) = neg.getChild() }

  override string getAPrimaryQlClass() { result = "Negation" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getFormula") and result = this.getFormula()
  }
}

/** An expression, such as `x+4`. */
class Expr extends TExpr, AstNode { }

class ExprAnnotation extends TExprAnnotation, Expr {
  Generated::ExprAnnotation expr_anno;

  ExprAnnotation() { this = TExprAnnotation(expr_anno) }

  string getName() { result = expr_anno.getName().getValue() }

  string getAnnotationArgument() { result = expr_anno.getAnnotArg().getValue() }

  Expr getExpression() { toGenerated(result) = expr_anno.getChild() }

  override string getAPrimaryQlClass() { result = "ExprAnnotation" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getExpression") and result = this.getExpression()
  }
}

/** A function symbol, such as `+` or `*`. */
class FunctionSymbol extends string {
  FunctionSymbol() { this = "+" or this = "-" or this = "*" or this = "/" or this = "%" }
}

/**
 * A binary operation expression, such as `x + 3` or `y / 2`.
 */
class BinOpExpr extends TBinOpExpr, Expr { }

/**
 * An addition or subtraction expression.
 */
class AddSubExpr extends TAddSubExpr, BinOpExpr {
  Generated::AddExpr expr;
  FunctionSymbol operator;

  AddSubExpr() { this = TAddSubExpr(expr) and operator = expr.getChild().getValue() }

  /** Gets the left operand of the binary expression. */
  Expr getLeftOperand() { toGenerated(result) = expr.getLeft() }

  /* Gets the right operand of the binary expression. */
  Expr getRightOperand() { toGenerated(result) = expr.getRight() }

  /* Gets an operand of the binary expression. */
  Expr getAnOperand() { result = getLeftOperand() or result = getRightOperand() }

  /** Gets the operator of the binary expression. */
  FunctionSymbol getOperator() { result = operator }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getLeftOperand") and result = this.getLeftOperand()
    or
    pred = directMember("getRightOperand") and result = this.getRightOperand()
  }
}

/**
 * An addition expression, such as `x + y`.
 */
class AddExpr extends AddSubExpr {
  AddExpr() { operator = "+" }

  override string getAPrimaryQlClass() { result = "AddExpr" }
}

/**
 * A subtraction expression, such as `x - y`.
 */
class SubExpr extends AddSubExpr {
  SubExpr() { operator = "-" }

  override string getAPrimaryQlClass() { result = "SubExpr" }
}

/**
 * A multiplication, division, or modulo expression.
 */
class MulDivModExpr extends TMulDivModExpr, BinOpExpr {
  Generated::MulExpr expr;
  FunctionSymbol operator;

  MulDivModExpr() { this = TMulDivModExpr(expr) and operator = expr.getChild().getValue() }

  /** Gets the left operand of the binary expression. */
  Expr getLeftOperand() { toGenerated(result) = expr.getLeft() }

  /** Gets the right operand of the binary expression. */
  Expr getRightOperand() { toGenerated(result) = expr.getRight() }

  /** Gets an operand of the binary expression. */
  Expr getAnOperand() { result = getLeftOperand() or result = getRightOperand() }

  /** Gets the operator of the binary expression. */
  FunctionSymbol getOperator() { result = operator }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getLeftOperand") and result = this.getLeftOperand()
    or
    pred = directMember("getRightOperand") and result = this.getRightOperand()
  }
}

/**
 * A division expression, such as `x / y`.
 */
class DivExpr extends MulDivModExpr {
  DivExpr() { operator = "/" }

  override string getAPrimaryQlClass() { result = "DivExpr" }
}

/**
 * A multiplication expression, such as `x * y`.
 */
class MulExpr extends MulDivModExpr {
  MulExpr() { operator = "*" }

  override string getAPrimaryQlClass() { result = "MulExpr" }
}

/**
 * A modulo expression, such as `x % y`.
 */
class ModExpr extends MulDivModExpr {
  ModExpr() { operator = "%" }

  override string getAPrimaryQlClass() { result = "ModExpr" }
}

/**
 * A range expression, such as `[1 .. 10]`.
 */
class Range extends TRange, Expr {
  Generated::Range range;

  Range() { this = TRange(range) }

  /**
   * Gets the lower bound of the range.
   */
  Expr getLowEndpoint() { toGenerated(result) = range.getLower() }

  /**
   * Gets the upper bound of the range.
   */
  Expr getHighEndpoint() { toGenerated(result) = range.getUpper() }

  override string getAPrimaryQlClass() { result = "Range" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getLowEndpoint") and result = this.getLowEndpoint()
    or
    pred = directMember("getHighEndpoint") and result = this.getHighEndpoint()
  }
}

/**
 * A set literal expression, such as `[1,3,5,7]`.
 */
class Set extends TSet, Expr {
  Generated::SetLiteral set;

  Set() { this = TSet(set) }

  /**
   * Gets the ith element in the set literal expression.
   */
  Expr getElement(int i) { toGenerated(result) = set.getChild(i) }

  override string getAPrimaryQlClass() { result = "Set" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    exists(int i | pred = indexedMember("getElement", i) and result = getElement(i))
  }
}

/** A unary operation expression, such as `-(x*y)` */
class UnaryExpr extends TUnaryExpr, Expr {
  Generated::UnaryExpr unaryexpr;

  UnaryExpr() { this = TUnaryExpr(unaryexpr) }

  /** Gets the operand of the unary expression. */
  Expr getOperand() { toGenerated(result) = unaryexpr.getChild(1) }

  /** Gets the operator of the unary expression as a string. */
  FunctionSymbol getOperator() { result = unaryexpr.getChild(0).toString() }

  override string getAPrimaryQlClass() { result = "UnaryExpr" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getOperand") and result = this.getOperand()
  }
}

/** A "don't care" expression, denoted by `_`. */
class DontCare extends TDontCare, Expr {
  Generated::Underscore dontcare;

  DontCare() { this = TDontCare(dontcare) }

  override string getAPrimaryQlClass() { result = "DontCare" }
}

/** A module expression. */
class ModuleExpr extends TModuleExpr, ModuleRef {
  Generated::ModuleExpr me;

  ModuleExpr() { this = TModuleExpr(me) }

  /**
   * Gets the name of this module expression. For example, the name of
   *
   * ```ql
   * Foo::Bar
   * ```
   *
   * is `Bar`.
   */
  string getName() {
    result = me.getName().getValue()
    or
    not exists(me.getName()) and result = me.getChild().(Generated::SimpleId).getValue()
  }

  /**
   * Gets the qualifier of this module expression. For example, the qualifier of
   *
   * ```ql
   * Foo::Bar::Baz
   * ```
   *
   * is `Foo::Bar`.
   */
  ModuleExpr getQualifier() { result = TModuleExpr(me.getChild()) }

  final override FileOrModule getResolvedModule() { resolveModuleExpr(this, result) }

  final override string toString() { result = this.getName() }

  override string getAPrimaryQlClass() { result = "ModuleExpr" }

  override AstNode getAChild(string pred) {
    result = super.getAChild(pred)
    or
    pred = directMember("getQualifier") and result = this.getQualifier()
  }
}

private AstNode noParent() { not exists(result.getParent()) and not result instanceof TopLevel }

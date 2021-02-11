private import ruby
private import codeql_ruby.CFG
private import codeql_ruby.dataflow.SSA
private import DataFlowPublic
private import DataFlowDispatch

abstract class NodeImpl extends Node {
  /** Do not call: use `getEnclosingCallable()` instead. */
  abstract CfgScope getCfgScope();

  /** Do not call: use `getLocation()` instead. */
  abstract Location getLocationImpl();

  /** Do not call: use `toString()` instead. */
  abstract string toStringImpl();
}

private class ExprNodeImpl extends ExprNode, NodeImpl {
  override CfgScope getCfgScope() { result = this.getExprNode().getExpr().getCfgScope() }

  override Location getLocationImpl() { result = this.getExprNode().getLocation() }

  override string toStringImpl() { result = this.getExprNode().toString() }
}

/** Provides predicates related to local data flow. */
module LocalFlow {
  private import codeql_ruby.dataflow.internal.SsaImpl

  /**
   * Holds if `nodeFrom` is a last node referencing SSA definition `def`, which
   * can reach `next`.
   */
  private predicate localFlowSsaInput(Node nodeFrom, Ssa::Definition def, Ssa::Definition next) {
    exists(BasicBlock bb, int i | lastRefBeforeRedef(def, bb, i, next) |
      def = nodeFrom.(SsaDefinitionNode).getDefinition() and
      def.definesAt(_, bb, i)
      or
      exists(CfgNodes::ExprCfgNode e |
        e = nodeFrom.asExpr() and
        e = bb.getNode(i) and
        e.getExpr() instanceof VariableReadAccess
      )
    )
  }

  /**
   * Holds if there is a local flow step from `nodeFrom` to `nodeTo` involving
   * SSA definition `def.
   */
  predicate localSsaFlowStep(Ssa::Definition def, Node nodeFrom, Node nodeTo) {
    // Flow from assignment into SSA definition
    exists(CfgNodes::ExprNodes::AssignmentCfgNode a, BasicBlock bb, int i |
      def.definesAt(_, bb, i) and
      a = bb.getNode(i) and
      a.getExpr() instanceof AssignExpr and
      nodeFrom.asExpr() = a.getRhs() and
      nodeTo.(SsaDefinitionNode).getDefinition() = def
    )
    or
    // Flow from SSA definition to first read
    def = nodeFrom.(SsaDefinitionNode).getDefinition() and
    nodeTo.asExpr() = def.getAFirstRead()
    or
    // Flow from read to next read
    exists(
      CfgNodes::ExprNodes::VariableReadAccessCfgNode read1,
      CfgNodes::ExprNodes::VariableReadAccessCfgNode read2
    |
      def.hasAdjacentReads(read1, read2) and
      nodeTo.asExpr() = read2
    |
      nodeFrom.asExpr() = read1
      or
      read1 = nodeFrom.(PostUpdateNode).getPreUpdateNode().asExpr()
    )
    or
    // Flow into phi node
    exists(Ssa::PhiNode phi |
      localFlowSsaInput(nodeFrom, def, phi) and
      phi = nodeTo.(SsaDefinitionNode).getDefinition() and
      def = phi.getAnInput()
    )
    // TODO
    // or
    // // Flow into uncertain SSA definition
    // exists(LocalFlow::UncertainExplicitSsaDefinition uncertain |
    //   localFlowSsaInput(nodeFrom, def, uncertain) and
    //   uncertain = nodeTo.(SsaDefinitionNode).getDefinition() and
    //   def = uncertain.getPriorDefinition()
    // )
  }
}

/** An argument of a call (including qualifier arguments). */
private class Argument extends Expr {
  private Call call;
  private int arg;

  Argument() { this = call.getArgument(arg) }

  /** Holds if this expression is the `i`th argument of `c`. */
  predicate isArgumentOf(Expr c, int i) { c = call and i = arg }
}

/** A collection of cached types and predicates to be evaluated in the same stage. */
cached
private module Cached {
  cached
  newtype TNode =
    TExprNode(CfgNodes::ExprCfgNode n) or
    TReturningNode(CfgNodes::ReturningCfgNode n) or
    TSsaDefinitionNode(Ssa::Definition def) or
    TParameterNode(Parameter p) or
    TExprPostUpdateNode(CfgNodes::ExprCfgNode n) { n.getNode() instanceof Argument }

  /**
   * This is the local flow predicate that is used as a building block in global
   * data flow. It excludes SSA flow through instance fields, as flow through fields
   * is handled by the global data-flow library, but includes various other steps
   * that are only relevant for global flow.
   */
  cached
  predicate simpleLocalFlowStep(Node nodeFrom, Node nodeTo) {
    exists(Ssa::Definition def | LocalFlow::localSsaFlowStep(def, nodeFrom, nodeTo))
    or
    nodeFrom.asExpr() = nodeTo.asExpr().(CfgNodes::ExprNodes::AssignExprCfgNode).getRhs()
    or
    nodeFrom.asExpr() = nodeTo.asExpr().(CfgNodes::ExprNodes::ExprSequenceCfgNode).getLastExpr()
    or
    nodeFrom.asExpr() = nodeTo.asExpr().(CfgNodes::ExprNodes::ConditionalExprCfgNode).getBranch(_)
    or
    nodeFrom.asExpr() = nodeTo.asExpr().(CfgNodes::ExprNodes::CaseExprCfgNode).getBranch(_)
    or
    exists(CfgNodes::ExprCfgNode exprTo, ReturningStatementNode n |
      nodeFrom = n and
      exprTo = nodeTo.asExpr() and
      n.getReturningNode().getNode() instanceof BreakStmt and
      exprTo.getNode() instanceof Loop and
      nodeTo.asExpr().getAPredecessor(any(SuccessorTypes::BreakSuccessor s)) = n.getReturningNode()
    )
    or
    nodeFrom.asExpr() = nodeTo.(ReturningStatementNode).getReturningNode().getReturnedValueNode()
    or
    nodeTo.asExpr() =
      any(CfgNodes::ExprNodes::ForExprCfgNode for |
        exists(SuccessorType s |
          not s instanceof SuccessorTypes::BreakSuccessor and
          exists(for.getAPredecessor(s))
        ) and
        nodeFrom.asExpr() = for.getValue()
      )
  }

  cached
  newtype TContent = TTodoContent() // stub

  /** Holds if `n` should be hidden from path explanations. */
  cached
  predicate nodeIsHidden(Node n) {
    exists(Ssa::Definition def | def = n.(SsaDefinitionNode).getDefinition() |
      def instanceof Ssa::PhiNode
    )
  }
}

import Cached

/** An SSA definition, viewed as a node in a data flow graph. */
class SsaDefinitionNode extends NodeImpl, TSsaDefinitionNode {
  Ssa::Definition def;

  SsaDefinitionNode() { this = TSsaDefinitionNode(def) }

  /** Gets the underlying SSA definition. */
  Ssa::Definition getDefinition() { result = def }

  override CfgScope getCfgScope() { result = def.getBasicBlock().getScope() }

  override Location getLocationImpl() { result = def.getLocation() }

  override string toStringImpl() { result = def.toString() }
}

/**
 * A value returning statement, viewed as a node in a data flow graph.
 *
 * Note that because of control-flow splitting, one `ReturningStmt` may correspond
 * to multiple `ReturningStatementNode`s, just like it may correspond to multiple
 * `ControlFlow::Node`s.
 */
class ReturningStatementNode extends NodeImpl, TReturningNode {
  private CfgNodes::ReturningCfgNode n;

  ReturningStatementNode() { this = TReturningNode(n) }

  /** Gets the expression corresponding to this node. */
  CfgNodes::ReturningCfgNode getReturningNode() { result = n }

  override CfgScope getCfgScope() { result = n.getScope() }

  override Location getLocationImpl() { result = n.getLocation() }

  override string toStringImpl() { result = n.toString() }
}

private module ParameterNodes {
  abstract private class ParameterNodeImpl extends ParameterNode, NodeImpl { }

  /**
   * The value of an explicit parameter at function entry, viewed as a node in a data
   * flow graph.
   */
  class ExplicitParameterNode extends ParameterNodeImpl, TParameterNode {
    private Parameter parameter;

    ExplicitParameterNode() { this = TParameterNode(parameter) }

    override Parameter getParameter() { result = parameter }

    override predicate isParameterOf(Callable c, int i) { c.getParameter(i) = parameter }

    override CfgScope getCfgScope() { result = parameter.getCallable() }

    override Location getLocationImpl() { result = parameter.getLocation() }

    override string toStringImpl() { result = parameter.toString() }
  }
}

import ParameterNodes

/** A data-flow node that represents a call argument. */
abstract class ArgumentNode extends Node {
  /** Holds if this argument occurs at the given position in the given call. */
  cached
  abstract predicate argumentOf(DataFlowCall call, int pos);

  /** Gets the call in which this node is an argument. */
  final DataFlowCall getCall() { this.argumentOf(result, _) }
}

private module ArgumentNodes {
  /** A data-flow node that represents an explicit call argument. */
  class ExplicitArgumentNode extends ArgumentNode {
    ExplicitArgumentNode() { this.asExpr().getExpr() instanceof Argument }

    override predicate argumentOf(DataFlowCall call, int pos) {
      this.asExpr() = call.getReceiver() and
      pos = -1
      or
      this.asExpr() = call.getArgument(pos)
    }
  }
}

import ArgumentNodes

/** A data-flow node that represents a value returned by a callable. */
abstract class ReturnNode extends Node {
  /** Gets the kind of this return node. */
  abstract ReturnKind getKind();
}

private module ReturnNodes {
  private predicate isValid(CfgNodes::ReturningCfgNode node) {
    exists(ReturningStmt stmt, Callable scope |
      stmt = node.getNode() and
      scope = node.getScope()
    |
      stmt instanceof ReturnStmt and
      (scope instanceof Method or scope instanceof SingletonMethod or scope instanceof Lambda)
      or
      stmt instanceof NextStmt and
      (scope instanceof Block or scope instanceof Lambda)
      or
      stmt instanceof BreakStmt and
      (scope instanceof Block or scope instanceof Lambda)
    )
  }

  /**
   * A data-flow node that represents an expression returned by a callable,
   * either using an explict `return` statement or as the expression of a method body.
   */
  class ExplicitReturnNode extends ReturnNode, ReturningStatementNode {
    private CfgNodes::ReturningCfgNode n;

    ExplicitReturnNode() {
      isValid(this.getReturningNode()) and
      n.getASuccessor().(CfgNodes::AnnotatedExitNode).isNormal() and
      n.getScope() instanceof Callable
    }

    override ReturnKind getKind() {
      if n.getNode() instanceof BreakStmt
      then result instanceof BreakReturnKind
      else result instanceof NormalReturnKind
    }
  }

  class ExprReturnNode extends ReturnNode, ExprNode {
    ExprReturnNode() {
      this.getExprNode().getASuccessor().(CfgNodes::AnnotatedExitNode).isNormal() and
      this.getEnclosingCallable() instanceof Callable
    }

    override ReturnKind getKind() { result instanceof NormalReturnKind }
  }
}

import ReturnNodes

/** A data-flow node that represents the output of a call. */
abstract class OutNode extends Node {
  /** Gets the underlying call, where this node is a corresponding output of kind `kind`. */
  cached
  abstract DataFlowCall getCall(ReturnKind kind);
}

private module OutNodes {
  /**
   * A data-flow node that reads a value returned directly by a callable,
   * either via a call or a `yield` of a block.
   */
  class ExprOutNode extends OutNode, ExprNode {
    private DataFlowCall call;

    ExprOutNode() { call = this.getExprNode() }

    override DataFlowCall getCall(ReturnKind kind) {
      result = call and
      kind instanceof NormalReturnKind
    }
  }
}

import OutNodes

predicate jumpStep(Node pred, Node succ) { none() }

predicate storeStep(Node node1, Content c, Node node2) { none() }

predicate readStep(Node node1, Content c, Node node2) { none() }

/**
 * Holds if values stored inside content `c` are cleared at node `n`. For example,
 * any value stored inside `f` is cleared at the pre-update node associated with `x`
 * in `x.f = newValue`.
 */
predicate clearsContent(Node n, Content c) { storeStep(_, c, n) }

private newtype TDataFlowType = TTodoDataFlowType()

class DataFlowType extends TDataFlowType {
  string toString() { result = "" }
}

/** Gets the type of `n` used for type pruning. */
DataFlowType getNodeType(NodeImpl n) { any() }

/** Gets a string representation of a `DataFlowType`. */
string ppReprType(DataFlowType t) { result = t.toString() }

/**
 * Holds if `t1` and `t2` are compatible, that is, whether data can flow from
 * a node of type `t1` to a node of type `t2`.
 */
pragma[inline]
predicate compatibleTypes(DataFlowType t1, DataFlowType t2) { any() }

/**
 * A node associated with an object after an operation that might have
 * changed its state.
 *
 * This can be either the argument to a callable after the callable returns
 * (which might have mutated the argument), or the qualifier of a field after
 * an update to the field.
 *
 * Nodes corresponding to AST elements, for example `ExprNode`, usually refer
 * to the value before the update.
 */
abstract class PostUpdateNode extends Node {
  /** Gets the node before the state update. */
  abstract Node getPreUpdateNode();
}

private module PostUpdateNodes {
  class ExprPostUpdateNode extends PostUpdateNode, NodeImpl, TExprPostUpdateNode {
    private CfgNodes::ExprCfgNode e;

    ExprPostUpdateNode() { this = TExprPostUpdateNode(e) }

    override ExprNode getPreUpdateNode() { e = result.getExprNode() }

    override CfgScope getCfgScope() { result = e.getExpr().getCfgScope() }

    override Location getLocationImpl() { result = e.getLocation() }

    override string toStringImpl() { result = "[post] " + e.toString() }
  }
}

private import PostUpdateNodes

/** A node that performs a type cast. */
class CastNode extends Node {
  CastNode() { none() }
}

class DataFlowExpr = CfgNodes::ExprCfgNode;

int accessPathLimit() { result = 5 }

/** The unit type. */
private newtype TUnit = TMkUnit()

/** The trivial type with a single element. */
class Unit extends TUnit {
  /** Gets a textual representation of this element. */
  string toString() { result = "unit" }
}

/**
 * Holds if `n` does not require a `PostUpdateNode` as it either cannot be
 * modified or its modification cannot be observed, for example if it is a
 * freshly created object that is not saved in a variable.
 *
 * This predicate is only used for consistency checks.
 */
predicate isImmutableOrUnobservable(Node n) { none() }

/**
 * Holds if the node `n` is unreachable when the call context is `call`.
 */
predicate isUnreachableInCall(Node n, DataFlowCall call) { none() }

/**
 * A guard that validates some expression.
 */
class BarrierGuard extends Expr {
  BarrierGuard() { none() }

  Node getAGuardedNode() { none() }
}
// switched away from this; probably delete


function compareNaive(left, right, path, pathFlags) {
  if (JSON.stringify(left) == JSON.stringify(right)) {
    return [];
  }

  const changes = [];
  const leftComplex = typeof left == 'object' && left != null;
  const rightComplex = typeof right == 'object' && right != null;
  const recursePathFlags = [];

  if (typeof left == 'undefined') {
    recursePathFlags.push('parent:CREATE');
    changes.push({
      path,
      pathFlags,
      change: 'value.CREATE',
      rightType: typeof right,
      rightValue: typeof right != 'object' ? right : undefined,
    });
  } else if (typeof right == 'undefined') {
    recursePathFlags.push('parent:DELETE');
    changes.push({
      path,
      pathFlags,
      change: 'value.DELETE',
      leftType: typeof left,
      leftValue: typeof left != 'object' ? left : undefined,
    });
  } else if (!leftComplex && !rightComplex) {
    return [
      {
        path,
        pathFlags,
        change: 'value.UPDATE',
        leftType: typeof left,
        leftValue: left,
        rightType: typeof right,
        rightValue: right,
      },
    ];
  }

  if (!leftComplex && !rightComplex) {
    return changes;
  }
  
  let leftRecurse = left ? (Array.isArray(left) ? 'array' : typeof left) : undefined;
  let rightRecurse = right ? (Array.isArray(right) ? 'array' : typeof right) : undefined;

  if (leftRecurse && rightRecurse && leftRecurse != rightRecurse) {
    if (leftRecurse == 'array' && rightRecurse == 'object' && left.length == 0) {
      // can workaround empty object being serialized as array
      leftRecurse = 'object';
    } else if (leftRecurse == 'object' && rightRecurse == 'array' && right.length == 0) {
      // can workaround empty object being serialized as array
      rightRecurse = 'object';
    } else {
      // process.stderr.write(`TODO - decide how to diff mixed recursive strategies (${path.join('/')}, ${leftRecurse} vs ${rightRecurse})\n`);

      // treat it as a delete/create
      changes.push(...compareNaive(left, undefined, path, [...pathFlags, 'scope:TYPE-CHANGE']));
      changes.push(...compareNaive(undefined, right, path, [...pathFlags, 'scope:TYPE-CHANGE']));

      return changes;
    }
  }

  let recurseKeys = [];

  if (leftRecurse == 'array' || rightRecurse == 'array') {
    recurseKeys = [...Array(Math.max(
      left?.length || 0,
      right?.length || 0,
    )).keys()];
  } else {
    recurseKeys = [...new Set([
      ...Object.keys(left || {}),
      ...Object.keys(right || {}),
    ])];
  }

  for (const recurseKey of recurseKeys) {
    changes.push(...compareNaive(
      typeof left == 'undefined' ? undefined : left[recurseKey],
      typeof right == 'undefined' ? undefined : right[recurseKey],
      [...path, recurseKey],
      [...new Set([...pathFlags, ...recursePathFlags])],
    ));
  }

  return changes;
}

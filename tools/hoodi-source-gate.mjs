import { execFileSync } from 'node:child_process';

export function currentSource() {
  return {
    contractsCommit: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
    worktreeDirty: execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim().length > 0,
  };
}

export function assertSourceLineage(previous, current) {
  if (previous.contractsCommit !== current.contractsCommit || (!previous.worktreeDirty && current.worktreeDirty)) {
    throw new Error('source commit or clean worktree changed since previous evidence');
  }
}

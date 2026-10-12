module sharedState {
  import multiIntentProfiles.* from "../multi/profiles"
  export multiIntentProfiles.*
  type ObjectRequest = { intent: int, account: int, object: int, operation: int,
    key: int, expected: int, content: int }
  type ObjectReceipt = { request: ObjectRequest, applied: bool, version: int, value: int }
  type SharedObject = { version: int, content: int, receipts: Set[ObjectReceipt],
    writes: List[ObjectReceipt], observations: List[{ intent: int, receipt: ObjectReceipt }],
    replays: int, reads: int }
  var sharedObject: SharedObject
  pure def objectRequest(i: int): ObjectRequest =
    { intent: i, account: 1, object: 1, operation: 1, key: i, expected: 0, content: i }
  pure val sharedRequestA: SubmissionRequest = { ...request, definition: { ...definition, policy: RetryOnce } }
  action sharedInit = all { multiInit, sharedObject' = {
    version: 0, content: 0, receipts: Set(), writes: List(), observations: List(), replays: 0, reads: 0 } }
    .then(all { openRound(1, 1, Set({ ...dependencyA, request: sharedRequestA }, dependencyB)), holdObject })
    .then(all { multiSend(1, sharedRequestA), holdObject }).then(all { multiSubmit(1, sharedRequestA), holdObject })
    .then(all { multiSend(1, requestB), holdObject }).then(all { multiSubmit(1, requestB), holdObject })
  action holdObject = sharedObject' = sharedObject
}

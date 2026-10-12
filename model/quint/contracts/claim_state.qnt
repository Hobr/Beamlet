// Claim storage commit and delivery are separate; allocations survive process loss.
module claimState {
  import beamletExecution.* from "../beamletExecution"
  export beamletExecution.*
  type ClaimRequest = { exec: int, worker: int, incarnation: int, expected: int }
  type ClaimReply = { request: ClaimRequest, token: Token }
  type ClaimWire = { requests: Set[ClaimRequest], replies: Set[ClaimReply],
    received: Set[ClaimReply], replays: int, losses: int }
  var claimJournal: Set[ClaimReply]
  var claimWire: ClaimWire
  action claimInit = all { init, claimJournal' = Set(), claimWire' = {
    requests: Set(), replies: Set(), received: Set(), replays: 0, losses: 0 } }
  action holdClaims = all { claimJournal' = claimJournal, claimWire' = claimWire }
  action holdCore = all { authority' = authority, workers' = workers, network' = network,
    external' = external, clock' = clock }
}

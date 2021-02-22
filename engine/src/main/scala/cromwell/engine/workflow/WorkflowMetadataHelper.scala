package cromwell.engine.workflow

import java.time.OffsetDateTime

import akka.actor.ActorRef
import cromwell.core._
import cromwell.services.metadata.{MetadataEvent, MetadataKey, MetadataValue}
import cromwell.services.metadata.MetadataService._

import scala.collection.immutable

trait WorkflowMetadataHelper {

  def serviceRegistryActor: ActorRef
  
  def pushWorkflowStart(workflowId: WorkflowId) = {
    val startEvent = MetadataEvent(
      MetadataKey(workflowId, None, WorkflowMetadataKeys.StartTime),
      MetadataValue(OffsetDateTime.now)
    )
    serviceRegistryActor ! PutMetadataAction(startEvent)
  }
  
  def pushWorkflowEnd(workflowId: WorkflowId): MetadataEvent = {
    val metadataEventMsg = MetadataEvent(
      MetadataKey(workflowId, None, WorkflowMetadataKeys.EndTime),
      MetadataValue(OffsetDateTime.now)
    )
//    serviceRegistryActor ! PutMetadataAction(metadataEventMsg)

    metadataEventMsg
  }
  
  def pushWorkflowFailures(workflowId: WorkflowId, failures: List[Throwable]) = {
    val failureEvents = failures flatMap { r => throwableToMetadataEvents(MetadataKey(workflowId, None, s"${WorkflowMetadataKeys.Failures}"), r) }
    serviceRegistryActor ! PutMetadataAction(failureEvents)
  }

  def pushWorkflowFailuresForWA(workflowId: WorkflowId, failures: List[Throwable]): Seq[MetadataEvent] = {
    val failureEvents = failures flatMap { r => throwableToMetadataEvents(MetadataKey(workflowId, None, s"${WorkflowMetadataKeys.Failures}"), r) }
//    serviceRegistryActor ! PutMetadataAction(failureEvents)
    failureEvents
  }
  
  def pushCurrentStateToMetadataService(workflowId: WorkflowId, workflowState: WorkflowState): Unit = {
    val metadataEventMsg = MetadataEvent(MetadataKey(workflowId, None, WorkflowMetadataKeys.Status),
      MetadataValue(workflowState))
    serviceRegistryActor ! PutMetadataAction(metadataEventMsg)
  }
  
}

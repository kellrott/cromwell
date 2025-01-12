package cromwell.engine

import java.time.OffsetDateTime
import java.util.UUID

import akka.testkit._
import cats.data.{NonEmptyList, NonEmptyVector}
import common.assertion.CromwellTimeoutSpec
import cromwell.core._
import cromwell.core.abort.{AbortResponse, WorkflowAbortFailureResponse, WorkflowAbortRequestedResponse, WorkflowAbortedResponse}
import cromwell.engine.workflow.{CoordinatedWorkflowStoreActorBuilder, SqlWorkflowStoreBuilder}
import cromwell.engine.workflow.WorkflowManagerActor.WorkflowNotFoundException
import cromwell.engine.workflow.workflowstore.SqlWorkflowStore.WorkflowStoreState
import cromwell.engine.workflow.workflowstore.WorkflowStoreActor._
import cromwell.engine.workflow.workflowstore.WorkflowStoreCoordinatedAccessActor.WriteHeartbeats
import cromwell.engine.workflow.workflowstore.WorkflowStoreEngineActor.{NewWorkflowsToStart, NoNewWorkflowsToStart}
import cromwell.engine.workflow.workflowstore.WorkflowStoreSubmitActor.{WorkflowSubmittedToStore, WorkflowsBatchSubmittedToStore}
import cromwell.engine.workflow.workflowstore._
import cromwell.services.metadata.MetadataQuery
import cromwell.services.metadata.MetadataService.{GetMetadataAction, MetadataLookupResponse}
import cromwell.services.metadata.impl.ReadDatabaseMetadataWorkerActor
import cromwell.util.EncryptionSpec
import cromwell.util.SampleWdl.HelloWorld
import cromwell.{CromwellTestKitSpec, CromwellTestKitWordSpec}
import mouse.all._
import org.scalatest.BeforeAndAfter
import org.scalatest.concurrent.Eventually
import org.scalatest.matchers.should.Matchers
import org.specs2.mock.Mockito

import scala.concurrent.Await
import scala.concurrent.duration._
import scala.language.postfixOps

class WorkflowStoreActorSpec extends CromwellTestKitWordSpec with CoordinatedWorkflowStoreActorBuilder with SqlWorkflowStoreBuilder with Matchers with BeforeAndAfter with Mockito with Eventually with CromwellTimeoutSpec {
  private val helloWorldSourceFiles = HelloWorld.asWorkflowSources().asInstanceOf[WorkflowSourceFilesWithoutImports]
  private val helloWorldSourceFilesOnHold = HelloWorld.asWorkflowSources(workflowOnHold = true)
  private val helloCwlWorldSourceFiles =
    HelloWorld.asWorkflowSources(workflowType = Option("CWL"), workflowTypeVersion = Option("v1.0"))

  /**
    * Fold down a list of WorkflowToStart's, checking that their IDs are all unique
    */
  private def checkDistinctIds(list: Iterable[WorkflowToStart]): Boolean = {
    def folderFunction(knownDistinct: (List[WorkflowToStart], Boolean), next: WorkflowToStart) = {
      val (list, distinct) = knownDistinct
      if (!distinct) {
        (list :+ next, false)
      }
      else {
        (list :+ next, !list.map(_.id).contains(next.id))
      }
    }

    list.foldLeft((List.empty[WorkflowToStart], true))(folderFunction)._2
  }

  private val workflowHeartbeatConfig = WorkflowHeartbeatConfig(rootConfig)

  "The WorkflowStoreActor" should {
    "return an ID for a submitted workflow" in {
      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-ReturnIdForSubmitted"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-ReturnIdForSubmitted"
      )
      storeActor ! SubmitWorkflow(helloWorldSourceFiles)
      expectMsgType[WorkflowSubmittedToStore](10 seconds)
    }

    "check if workflow state is 'On Hold' when workflowOnHold = true" in {
      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-CheckOnHold"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-CheckOnHold"
      )
      storeActor ! SubmitWorkflow(helloWorldSourceFilesOnHold)
      expectMsgPF(10 seconds) {
        case submit: WorkflowSubmittedToStore => submit.state shouldBe WorkflowOnHold
      }
    }

    "return 3 IDs for a batch submission of 3" in {
      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-ReturnIdsForBatch"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-ReturnIdsForBatch"
      )
      storeActor ! BatchSubmitWorkflows(NonEmptyList.of(helloWorldSourceFiles, helloWorldSourceFiles, helloWorldSourceFiles))
      expectMsgPF(10 seconds) {
        case WorkflowsBatchSubmittedToStore(ids, WorkflowSubmitted) => ids.toList.size shouldBe 3
      }
    }

    "fetch exactly N workflows" in {
      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-FetchExactlyN"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-FetchExactlyN"
      )
      storeActor ! BatchSubmitWorkflows(NonEmptyList.of(helloWorldSourceFiles, helloWorldSourceFiles, helloCwlWorldSourceFiles))
      val insertedIds = expectMsgType[WorkflowsBatchSubmittedToStore](10 seconds).workflowIds.toList

      storeActor ! FetchRunnableWorkflows(2, Set.empty)
      expectMsgPF(10 seconds) {
        case NewWorkflowsToStart(workflowNel) =>
          workflowNel.toList.size shouldBe 2
          checkDistinctIds(workflowNel.toList) shouldBe true
          workflowNel map {
            case WorkflowToStart(id, _, sources, state, _) =>
              insertedIds.contains(id) shouldBe true
              sources shouldBe helloWorldSourceFiles
              state shouldBe Submitted
          }
      }

      storeActor ! FetchRunnableWorkflows(1, Set.empty)
      expectMsgPF(10 seconds) {
        case NewWorkflowsToStart(workflowNel) =>
          workflowNel.toList.size shouldBe 1
          checkDistinctIds(workflowNel.toList) shouldBe true
          workflowNel map {
            case WorkflowToStart(id, _, sources, state, _) =>
              insertedIds.contains(id) shouldBe true
              sources shouldBe helloCwlWorldSourceFiles
              state shouldBe Submitted
          }
      }
    }

    "fetch encrypted and cleared workflow options" in {
      EncryptionSpec.assumeAes256Cbc()

      val optionedSourceFiles = HelloWorld.asWorkflowSources(workflowOptions =
        s"""|{
            |  "key": "value",
            |  "refresh_token": "it's a secret"
            |}
            |""".stripMargin)


      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-FetchEncryptedWorkflowOptions"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-FetchEncryptedWorkflowOptions"
      )
      storeActor ! BatchSubmitWorkflows(NonEmptyList.of(optionedSourceFiles))
      val insertedIds = expectMsgType[WorkflowsBatchSubmittedToStore](10 seconds).workflowIds.toList

      storeActor ! FetchRunnableWorkflows(1, Set.empty)
      expectMsgPF(10 seconds) {
        case NewWorkflowsToStart(workflowNel) =>
          workflowNel.toList.size should be(1)
          checkDistinctIds(workflowNel.toList) should be(true)
          workflowNel.toList.foreach {
            case WorkflowToStart(id, _, sources, state, _) =>
              insertedIds.contains(id) should be(true)
              sources.workflowSource should be(optionedSourceFiles.workflowSource)
              sources.inputsJson should be(optionedSourceFiles.inputsJson)
              state should be(Submitted)

              import spray.json._

              // We need to wait for workflow metadata to be flushed before we can successfully query for it
              eventually(timeout(15.seconds.dilated), interval(500.millis.dilated)) {
                val actorNameUniquificationString = UUID.randomUUID().toString.take(7)
                val readMetadataActor = system.actorOf(
                  ReadDatabaseMetadataWorkerActor.props(metadataReadTimeout = 30 seconds, metadataReadRowNumberSafetyThreshold = 20000),
                  s"ReadMetadataActor-FetchEncryptedOptions-$actorNameUniquificationString"
                )

                readMetadataActor ! GetMetadataAction(MetadataQuery.forWorkflow(id))
                expectMsgPF(10 seconds) {
                  case MetadataLookupResponse(_, eventList) =>
                    val optionsEvent = eventList.find(_.key.key == "submittedFiles:options").get
                    val clearedJsObject = optionsEvent.value.get.value.parseJson.asJsObject
                    clearedJsObject.fields("key") should be(JsString("value"))
                }
              }
          }
      }
    }

    "return only the remaining workflows if N is larger than size" in {
      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-ReturnOnlyRemaining"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-ReturnOnlyRemaining"
      )
      storeActor ! BatchSubmitWorkflows(NonEmptyList.of(helloWorldSourceFiles, helloWorldSourceFiles, helloWorldSourceFiles))
      val insertedIds = expectMsgType[WorkflowsBatchSubmittedToStore](10 seconds).workflowIds.toList

      storeActor ! FetchRunnableWorkflows(100, Set.empty)
      expectMsgPF(10 seconds) {
        case NewWorkflowsToStart(workflowNel) =>
          workflowNel.toList.size shouldBe 3
          checkDistinctIds(workflowNel.toList) shouldBe true
          workflowNel map {
            case WorkflowToStart(id, _, sources, state, _) =>
              insertedIds.contains(id) shouldBe true
              sources shouldBe helloWorldSourceFiles
              state shouldBe Submitted
          }
      }
    }

    "remain responsive if you ask to remove a workflow it doesn't have" in {
      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-RemainResponsiveForUnknown"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-RemainResponsiveForUnknown"
      )

      storeActor ! FetchRunnableWorkflows(100, Set.empty)
      expectMsgPF(10 seconds) {
        case NoNewWorkflowsToStart => // Great
        case x => fail(s"Unexpected response from supposedly empty WorkflowStore: $x")
      }
    }

    "abort an on hold workflow" in {
      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-AbortOnHold"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-AbortOnHold"
      )
      storeActor ! SubmitWorkflow(helloWorldSourceFiles.copy(workflowOnHold = true))
      val workflowId = expectMsgType[WorkflowSubmittedToStore](10.seconds).workflowId
      storeActor ! AbortWorkflowCommand(workflowId)
      val abortResponse = expectMsgType[AbortResponse](10.seconds)
      abortResponse should be(a[WorkflowAbortedResponse])
      abortResponse.asInstanceOf[WorkflowAbortedResponse].workflowId should be(workflowId)
    }

    "abort a submitted workflow with an empty heartbeat" in {
      runWithDatabase(databaseConfig) { store =>
        val storeActor = system.actorOf(
          WorkflowStoreActor.props(
            store,
            store |> access("coordinatedAccessActor-AbortSubmittedEmptyHeartbeat"),
            CromwellTestKitSpec.ServiceRegistryActorInstance,
            MockCromwellTerminator,
            abortAllJobsOnTerminate = false,
            workflowHeartbeatConfig
          ),
          "WorkflowStoreActor-AbortSubmittedEmptyHeartbeat"
        )
        storeActor ! SubmitWorkflow(helloWorldSourceFiles)
        val workflowId = expectMsgType[WorkflowSubmittedToStore](10.seconds).workflowId
        storeActor ! AbortWorkflowCommand(workflowId)
        val abortResponse = expectMsgType[AbortResponse](10.seconds)
        abortResponse should be(a[WorkflowAbortedResponse])
        abortResponse.asInstanceOf[WorkflowAbortedResponse].workflowId should be(workflowId)
      }
    }

    "abort a submitted workflow with a non-empty heartbeat" in {
      runWithDatabase(databaseConfig) { store =>
        val coordinatedAccess = store |> access("coordinatedAccessActor-AbortSubmittedNonEmptyHeartbeat")

        val storeActor = system.actorOf(
          WorkflowStoreActor.props(
            store,
            coordinatedAccess,
            CromwellTestKitSpec.ServiceRegistryActorInstance,
            MockCromwellTerminator,
            abortAllJobsOnTerminate = false,
            workflowHeartbeatConfig
          ),
          "WorkflowStoreActor-AbortSubmittedNonEmptyHeartbeat"
        )
        storeActor ! SubmitWorkflow(helloWorldSourceFiles)
        val workflowId = expectMsgType[WorkflowSubmittedToStore](10.seconds).workflowId
        coordinatedAccess.coordinatedWorkflowStoreAccessActor !
          WriteHeartbeats(NonEmptyVector.of((workflowId, OffsetDateTime.now())), OffsetDateTime.now())
        expectMsg(10.seconds, 1)
        storeActor ! AbortWorkflowCommand(workflowId)
        val abortResponse = expectMsgType[AbortResponse](10.seconds)
        abortResponse should be(a[WorkflowAbortedResponse])
        abortResponse.asInstanceOf[WorkflowAbortedResponse].workflowId should be(workflowId)
      }
    }

    "abort a running workflow with an empty heartbeat" in {
      runWithDatabase(databaseConfig) { store =>
        val storeActor = system.actorOf(
          WorkflowStoreActor.props(
            store,
            store |> access("coordinatedAccessActor-AbortRunningEmptyHeartbeat"),
            CromwellTestKitSpec.ServiceRegistryActorInstance,
            MockCromwellTerminator,
            abortAllJobsOnTerminate = false,
            workflowHeartbeatConfig
          ),
          "WorkflowStoreActor-AbortRunningEmptyHeartbeat"
        )
        storeActor ! SubmitWorkflow(helloWorldSourceFiles)
        val workflowId = expectMsgType[WorkflowSubmittedToStore](10.seconds).workflowId

        // Contact the db to change the status to running. Does not actually claim using the cromwellId.
        val futureUpdate = store.sqlDatabase.updateWorkflowState(
          workflowId.toString,
          WorkflowStoreState.Submitted.toString,
          WorkflowStoreState.Running.toString
        )

        Await.result(futureUpdate, 10.seconds.dilated) should be(1)

        storeActor ! AbortWorkflowCommand(workflowId)
        val abortResponse = expectMsgType[AbortResponse](10.seconds)
        abortResponse should be(a[WorkflowAbortRequestedResponse])
        abortResponse.asInstanceOf[WorkflowAbortRequestedResponse].workflowId should be(workflowId)
      }
    }

    "abort a running workflow with a non-empty heartbeat" in {
      runWithDatabase(databaseConfig) { store =>
        val coordinatedAccess = store |> access("coordinatedAccessActor-AbortRunningNonEmptyHeartbeat")
        val storeActor = system.actorOf(
          WorkflowStoreActor.props(
            store,
            coordinatedAccess,
            CromwellTestKitSpec.ServiceRegistryActorInstance,
            MockCromwellTerminator,
            abortAllJobsOnTerminate = false,
            workflowHeartbeatConfig
          ),
          "WorkflowStoreActor-AbortRunningNonEmptyHeartbeat"
        )
        storeActor ! SubmitWorkflow(helloWorldSourceFiles)
        val workflowId = expectMsgType[WorkflowSubmittedToStore](10.seconds).workflowId

        // Contact the db to change the status to running. Does not actually claim using the cromwellId.
        val futureUpdate = store.sqlDatabase.updateWorkflowState(
          workflowId.toString,
          WorkflowStoreState.Submitted.toString,
          WorkflowStoreState.Running.toString
        )

        Await.result(futureUpdate, 10.seconds.dilated) should be(1)

        coordinatedAccess.coordinatedWorkflowStoreAccessActor !
          WriteHeartbeats(NonEmptyVector.of((workflowId, OffsetDateTime.now())), OffsetDateTime.now())

        expectMsg(10.seconds, 1)
        storeActor ! AbortWorkflowCommand(workflowId)
        val abortResponse = expectMsgType[AbortResponse](10.seconds)
        abortResponse should be(a[WorkflowAbortRequestedResponse])
        abortResponse.asInstanceOf[WorkflowAbortRequestedResponse].workflowId should be(workflowId)
      }
    }

    "not abort a not found workflow" in {
      val store = new InMemoryWorkflowStore
      val storeActor = system.actorOf(
        WorkflowStoreActor.props(
          store,
          store |> access("coordinatedAccessActor-AbortNotFound"),
          CromwellTestKitSpec.ServiceRegistryActorInstance,
          MockCromwellTerminator,
          abortAllJobsOnTerminate = false,
          workflowHeartbeatConfig
        ),
        "WorkflowStoreActor-AbortNotFound"
      )
      val notFoundWorkflowId = WorkflowId.fromString("7ff8dff3-bc80-4500-af3b-57dbe7a6ecbb")
      storeActor ! AbortWorkflowCommand(notFoundWorkflowId)
      val abortResponse = expectMsgType[AbortResponse](10 seconds)
      abortResponse should be(a[WorkflowAbortFailureResponse])
      abortResponse.asInstanceOf[WorkflowAbortFailureResponse].workflowId should be(notFoundWorkflowId)
      abortResponse.asInstanceOf[WorkflowAbortFailureResponse].failure should be(a[WorkflowNotFoundException])
      abortResponse.asInstanceOf[WorkflowAbortFailureResponse].failure.getMessage should be(
        s"Couldn't abort 7ff8dff3-bc80-4500-af3b-57dbe7a6ecbb because no workflow with that ID is in progress")
    }

  }
}

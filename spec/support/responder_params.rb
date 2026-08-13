module ResponderParams
  def sample_params(responder_class)
    n = rand(1e5)
    params_by_responder = {
      SetValueResponder => { name: "set_value_#{n}"},
      ListOfValuesResponder => { name: "list_value_#{n}"},
      BasicCommandResponder => { command: "basic_command_#{n}" },
      LabelCommandResponder => { command: "label_command_#{n}", add_labels: ["label_#{n}"] },
      CloseIssueCommandResponder => { command: "close_command_#{n}" },
      ExternalServiceResponder => { name: "external_service_#{n}", command: "bot call service #{n}", url: "https://github.com/openjournals"},
      AddAndRemoveUserChecklistResponder => { template_file: "checklist.md" },
      ReviewerChecklistCommentResponder => { template_file: "checklist.md" },
      GithubActionResponder => { workflow_repo: "openjournals/joss-reviews", workflow_name: "compiler", command: "generate pdf" },
      InitialValuesResponder => { values: ["version", "target-repository"]},
      ListTeamMembersResponder => { command: "list editors", team_id: 3824115 },
      ExternalStartReviewResponder => { external_call: { url: "https://github.com/openjournals" }},
      UpdateCommentResponder => { command: "list final steps", template_file: "final-steps.md" },

      # NeuroLibre's responders declare required_params but were never
      # registered here, so instantiating them in the shared responder specs
      # raised a configuration error.
      Neurolibre::CoarResponder                     => {},
      Neurolibre::BinderBuildResponder            => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::BuildExtendedPdfResponder       => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::CacheDataResponder              => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::PreprintServerStatusResponder   => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::PreprintSyncDataResponder       => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::PreprintSyncPdfResponder        => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::PreviewServerStatusResponder    => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ProductionStartResponder        => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::SyncMystResponder               => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ZenodoCreateBucketsResponder    => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ZenodoFlushResponder            => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ZenodoPublishResponder          => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ZenodoStatusResponder           => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ZenodoUploadDataResponder       => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ZenodoUploadDockerResponder     => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ZenodoUploadMystResponder       => { external_call: { url: "https://neurolibre.org" } },
      Neurolibre::ZenodoUploadRepositoryResponder => { external_call: { url: "https://neurolibre.org" } },
    }

    params_by_responder[responder_class] || {}
  end
end

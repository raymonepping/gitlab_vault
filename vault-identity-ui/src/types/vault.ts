export interface TimelineEvent {
  time: string
  user_login: string
  user_email: string
  project_path: string
  pipeline_id: string
  job_id: string
  ref: string
  role: string
  path: string
  operation: string
  display_name?: string
  entity_id?: string
}

export interface HumanIdentity {
  count: number
  user_login: string
  user_email: string
  user_id: string
  projects: string[]
  namespaces: string[]
  pipelines: string[]
  jobs: string[]
  refs: string[]
  roles: string[]
  display_names: string[]
  entity_ids: string[]
  paths: string[]
  operations: string[]
  first_seen: string
  last_seen: string
}

export interface WorkloadIdentity {
  count: number
  project_path: string
  namespace_path: string
  pipeline_id: string
  job_id: string
  ref: string
  role: string
  users: Array<{
    user_login: string
    user_email: string
    user_id: string
  }>
  display_names: string[]
  entity_ids: string[]
  paths: string[]
  operations: string[]
  first_seen: string
  last_seen: string
}

export interface IdentityBundle {
  count: number
  display_name: string
  entity_id: string
  role: string
  user_login: string
  user_email: string
  user_id: string
  project_path: string
  namespace_path: string
  pipeline_id: string
  job_id: string
  ref: string
  paths: string[]
  operations: string[]
  first_seen: string
  last_seen: string
}

export interface SummaryMetrics {
  unique_humans: number
  unique_workloads: number
  secret_read_events: number
}

export interface VaultData {
  generated_at?: string
  source_file?: string
  filters?: Record<string, unknown>
  total_events: number
  read_events: number
  secret_read_events: number
  unique_humans: number
  unique_workloads: number
  timeline_events: TimelineEvent[]
  human_identities: HumanIdentity[]
  workload_identities: WorkloadIdentity[]
  full_identity_bundles: IdentityBundle[]
}

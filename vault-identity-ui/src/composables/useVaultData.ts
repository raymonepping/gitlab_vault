import { ref, onMounted } from "vue"
import type { VaultData } from "../types/vault"

export function useVaultData() {
  const data = ref<VaultData | null>(null)
  const loading = ref(true)

  onMounted(async () => {
    const res = await fetch("/data/vault_identity.json")
    data.value = await res.json()
    loading.value = false
  })

  return { data, loading }
}
<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { auth } from '$lib/auth.js';

  onMount(() => {
    // If we have a user, go to dashboard, else login
    const session = typeof window !== 'undefined' ? localStorage.getItem('flow_auth') : null;
    if (session) {
      goto('/dashboard');
    } else {
      goto('/login');
    }
  });
</script>

<div class="loading-screen">
  <div class="spinner"></div>
</div>

<style>
  .loading-screen {
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100vh;
    background: #f8fafc;
  }
  .spinner {
    width: 40px;
    height: 40px;
    border: 3px solid #e2e8f0;
    border-top-color: #3b82f6;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>

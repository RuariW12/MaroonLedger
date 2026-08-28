import axios from 'axios';
import { getToken, signOut } from './auth';

const api = axios.create({
  baseURL: '/api',
});

// Attach the bearer token per request rather than once at client creation, so
// a token acquired after load (or refreshed) is picked up without rebuilding
// the client.
api.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    // An expired or revoked token should return the user to sign-in rather
    // than leaving the UI in a state where every request silently fails.
    if (error.response?.status === 401) {
      signOut();
    }
    return Promise.reject(error);
  }
);

export const getMe = () => api.get('/me');
export const getSummary = (params) => api.get('/summary', { params });
export const getAccounts = () => api.get('/accounts');
export const getAccount = (id) => api.get(`/accounts/${id}`);
export const createAccount = (data) => api.post('/accounts', data);
export const getTransactions = (accountId) => api.get(`/accounts/${accountId}/transactions`);
export const createTransaction = (accountId, data) => api.post(`/accounts/${accountId}/transactions`, data);
export const getInsights = (params) => api.get('/insights', { params });

export default api;

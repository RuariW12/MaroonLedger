import axios from 'axios';

const api = axios.create({
  baseURL: '/api',
});

export const getAccounts = () => api.get('/accounts');
export const getAccount = (id) => api.get(`/accounts/${id}`);
export const createAccount = (data) => api.post('/accounts', data);
export const getTransactions = (accountId) => api.get(`/accounts/${accountId}/transactions`);
export const createTransaction = (accountId, data) => api.post(`/accounts/${accountId}/transactions`, data);

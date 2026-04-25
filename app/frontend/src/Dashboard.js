import { useState, useEffect } from 'react';
import { getAccounts, createAccount } from './api';

function Dashboard({ onSelectAccount }) {
  const [accounts, setAccounts] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ name: '', type: 'checking', balance: '' });

  useEffect(() => {
    getAccounts().then(res => setAccounts(res.data));
  }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    await createAccount({ ...form, balance: parseFloat(form.balance) || 0 });
    const res = await getAccounts();
    setAccounts(res.data);
    setForm({ name: '', type: 'checking', balance: '' });
    setShowForm(false);
  };

  const typeColors = {
    checking: 'bg-blue-100 text-blue-800',
    savings: 'bg-green-100 text-green-800',
    credit: 'bg-red-100 text-red-800',
    loan: 'bg-yellow-100 text-yellow-800',
  };

  const total = accounts.reduce((sum, a) => sum + a.balance, 0);

  return (
    <div className="max-w-4xl mx-auto p-6">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900">MaroonLedger</h1>
        <p className="text-gray-500 mt-1">Personal Finance Dashboard</p>
      </div>

      <div className="bg-gray-900 text-white rounded-lg p-6 mb-8">
        <p className="text-sm text-gray-400">Total Balance</p>
        <p className="text-4xl font-bold">${total.toFixed(2)}</p>
      </div>

      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-semibold">Accounts</h2>
        <button
          onClick={() => setShowForm(!showForm)}
          className="bg-gray-900 text-white px-4 py-2 rounded-lg hover:bg-gray-700"
        >
          {showForm ? 'Cancel' : '+ New Account'}
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleSubmit} className="bg-gray-50 rounded-lg p-4 mb-4 space-y-3">
          <input
            type="text"
            placeholder="Account name"
            value={form.name}
            onChange={e => setForm({ ...form, name: e.target.value })}
            className="w-full border rounded-lg px-3 py-2"
            required
          />
          <select
            value={form.type}
            onChange={e => setForm({ ...form, type: e.target.value })}
            className="w-full border rounded-lg px-3 py-2"
          >
            <option value="checking">Checking</option>
            <option value="savings">Savings</option>
            <option value="credit">Credit</option>
            <option value="loan">Loan</option>
          </select>
          <input
            type="number"
            placeholder="Starting balance"
            value={form.balance}
            onChange={e => setForm({ ...form, balance: e.target.value })}
            className="w-full border rounded-lg px-3 py-2"
            step="0.01"
          />
          <button type="submit" className="bg-gray-900 text-white px-4 py-2 rounded-lg hover:bg-gray-700">
            Create Account
          </button>
        </form>
      )}

      <div className="grid gap-4">
        {accounts.map(account => (
          <div
            key={account.id}
            onClick={() => onSelectAccount(account)}
            className="bg-white border rounded-lg p-4 cursor-pointer hover:shadow-md transition-shadow"
          >
            <div className="flex justify-between items-center">
              <div>
                <h3 className="font-semibold text-lg">{account.name}</h3>
                <span className={`text-xs px-2 py-1 rounded-full ${typeColors[account.type]}`}>
                  {account.type}
                </span>
              </div>
              <p className="text-2xl font-bold">${account.balance.toFixed(2)}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default Dashboard;

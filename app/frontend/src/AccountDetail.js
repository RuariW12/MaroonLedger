import { useState, useEffect } from 'react';
import { getTransactions, createTransaction } from './api';

function AccountDetail({ account, onBack }) {
  const [transactions, setTransactions] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ amount: '', category: '', description: '', date: '' });

  useEffect(() => {
    getTransactions(account.id).then(res => setTransactions(res.data));
  }, [account.id]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    await createTransaction(account.id, {
      ...form,
      amount: parseFloat(form.amount),
    });
    const res = await getTransactions(account.id);
    setTransactions(res.data);
    setForm({ amount: '', category: '', description: '', date: '' });
    setShowForm(false);
  };

  return (
    <div className="max-w-4xl mx-auto p-6">
      <button onClick={onBack} className="text-gray-500 hover:text-gray-900 mb-4">
        ← Back to Dashboard
      </button>

      <div className="flex justify-between items-center mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">{account.name}</h1>
          <p className="text-gray-500">{account.type}</p>
        </div>
        <p className="text-3xl font-bold">${account.balance.toFixed(2)}</p>
      </div>

      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-semibold">Transactions</h2>
        <button
          onClick={() => setShowForm(!showForm)}
          className="bg-gray-900 text-white px-4 py-2 rounded-lg hover:bg-gray-700"
        >
          {showForm ? 'Cancel' : '+ New Transaction'}
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleSubmit} className="bg-gray-50 rounded-lg p-4 mb-4 space-y-3">
          <input
            type="number"
            placeholder="Amount (negative for expenses)"
            value={form.amount}
            onChange={e => setForm({ ...form, amount: e.target.value })}
            className="w-full border rounded-lg px-3 py-2"
            step="0.01"
            required
          />
          <input
            type="text"
            placeholder="Category"
            value={form.category}
            onChange={e => setForm({ ...form, category: e.target.value })}
            className="w-full border rounded-lg px-3 py-2"
            required
          />
          <input
            type="text"
            placeholder="Description (optional)"
            value={form.description}
            onChange={e => setForm({ ...form, description: e.target.value })}
            className="w-full border rounded-lg px-3 py-2"
          />
          <input
            type="date"
            value={form.date}
            onChange={e => setForm({ ...form, date: e.target.value })}
            className="w-full border rounded-lg px-3 py-2"
          />
          <button type="submit" className="bg-gray-900 text-white px-4 py-2 rounded-lg hover:bg-gray-700">
            Add Transaction
          </button>
        </form>
      )}

      <div className="space-y-2">
        {transactions.length === 0 ? (
          <p className="text-gray-400 text-center py-8">No transactions yet</p>
        ) : (
          transactions.map(t => (
            <div key={t.id} className="bg-white border rounded-lg p-4 flex justify-between items-center">
              <div>
                <p className="font-medium">{t.category}</p>
                <p className="text-sm text-gray-500">{t.description}</p>
                <p className="text-xs text-gray-400">{new Date(t.date).toLocaleDateString()}</p>
              </div>
              <p className={`text-xl font-bold ${t.amount < 0 ? 'text-red-600' : 'text-green-600'}`}>
                {t.amount < 0 ? '-' : '+'}${Math.abs(t.amount).toFixed(2)}
              </p>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

export default AccountDetail;

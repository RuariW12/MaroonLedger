import { useState } from 'react';
import Dashboard from './Dashboard';
import AccountDetail from './AccountDetail';

function App() {
  const [selectedAccount, setSelectedAccount] = useState(null);

  return (
    <div className="min-h-screen bg-gray-100">
      {selectedAccount ? (
        <AccountDetail
          account={selectedAccount}
          onBack={() => setSelectedAccount(null)}
        />
      ) : (
        <Dashboard onSelectAccount={setSelectedAccount} />
      )}
    </div>
  );
}

export default App;
